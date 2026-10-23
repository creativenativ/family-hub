import CloudKit
import Foundation
import SwiftData

struct FamilySyncResult: Sendable {
    var pushed: Int
    var pulled: Int
    var removedLocally: Int
}

enum FamilySyncError: LocalizedError {
    case notInFamily
    case busy

    var errorDescription: String? {
        switch self {
        case .notInFamily: "Join or create a shared tribe before syncing."
        case .busy: "A sync is already running."
        }
    }
}

/// One synced model type, with its static requirements captured so the engine can loop over all of them.
private struct SyncEntity {
    let recordType: String
    let prefix: String
    let fetchLocal: (ModelContext) throws -> [any FamilySyncable]
    let makeNew: () -> any FamilySyncable

    static func of<T: FamilySyncable>(_ type: T.Type) -> SyncEntity {
        SyncEntity(
            recordType: T.syncRecordType,
            prefix: T.syncPrefix,
            fetchLocal: { try $0.fetch(FetchDescriptor<T>()) },
            makeNew: { T.makeForSync() }
        )
    }

    func recordName(for id: UUID) -> String {
        "\(prefix).\(id.uuidString)"
    }
}

@MainActor
@Observable
final class FamilySyncService {
    static let shared = FamilySyncService()

    private let container = CKContainer(identifier: FamilyCloudService.containerIdentifier)

    /// Order matters: members first so relationships resolve, budget items before their expenses.
    private let entities: [SyncEntity] = [
        .of(FamilyMember.self),
        .of(CalendarEvent.self),
        .of(Chore.self),
        .of(Recipe.self),
        .of(MealPlan.self),
        .of(FavoriteWeeklyMealPlan.self),
        .of(GroceryItem.self),
        .of(HouseholdNeed.self),
        .of(WishListItem.self),
        .of(BudgetItem.self),
        .of(BudgetExpense.self),
        .of(IncomeSource.self),
        .of(RecurringBill.self),
        .of(VoiceMemo.self),
        .of(PendingEmailImport.self),
    ]

    var isSyncing = false
    var lastSyncAt: Date?
    var lastErrorMessage: String?
    var lastResultSummary: String?
    private var isApplyingRemote = false
    private var needsResync = false
    private var pendingSyncTask: Task<Void, Never>?
    private var pendingDeletionRecordNames: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "FamilySync.pendingDeletions") ?? []
    )
    /// Record name → content fingerprint as of the last time this device synced it.
    /// Lets sync notice local edits and deletions without every screen having to report them.
    private var syncedFingerprints: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "FamilySync.fingerprints") as? [String: String]) ?? [:]

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func noteLocalDeletion(prefix: String, id: UUID) {
        pendingDeletionRecordNames.insert("\(prefix).\(id.uuidString)")
        persistPendingDeletions()
    }

    private func persistPendingDeletions() {
        UserDefaults.standard.set(Array(pendingDeletionRecordNames), forKey: "FamilySync.pendingDeletions")
    }

    private func persistFingerprints() {
        UserDefaults.standard.set(syncedFingerprints, forKey: "FamilySync.fingerprints")
    }

    // MARK: - Public

    func scheduleSync(membership: FamilyMembership?, modelContext: ModelContext, delayNanoseconds: UInt64 = 1_500_000_000) {
        guard membership != nil else { return }
        if isApplyingRemote || isSyncing {
            needsResync = true
            return
        }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled, let membership else { return }
            _ = try? await self.syncNow(membership: membership, modelContext: modelContext)
        }
    }

    /// Call after the app's own context saves, so local edits reach the tribe quickly.
    /// Saves made by sync itself are ignored.
    func noteLocalSave(membership: FamilyMembership?, modelContext: ModelContext) {
        guard !isSyncing, !isApplyingRemote else { return }
        scheduleSync(membership: membership, modelContext: modelContext, delayNanoseconds: 3_000_000_000)
    }

    /// Call when leaving a hub so a later empty-zone sync cannot wipe local data.
    func detachLocalDataFromFamily(modelContext: ModelContext) throws {
        for entity in entities {
            for model in try entity.fetchLocal(modelContext) {
                model.cloudSynced = false
            }
        }
        syncedFingerprints.removeAll()
        persistFingerprints()
        pendingDeletionRecordNames.removeAll()
        persistPendingDeletions()
        lastResultSummary = nil
        lastErrorMessage = nil
    }

    @discardableResult
    func syncNow(membership: FamilyMembership, modelContext: ModelContext) async throws -> FamilySyncResult {
        guard !isSyncing else {
            needsResync = true
            throw FamilySyncError.busy
        }

        isSyncing = true
        lastErrorMessage = nil
        defer {
            isSyncing = false
            if needsResync {
                needsResync = false
                scheduleSync(membership: membership, modelContext: modelContext, delayNanoseconds: 500_000_000)
            }
        }

        do {
            let zoneID = zoneID(for: membership)
            let database = database(for: membership)

            try seedFingerprintsIfNeeded(modelContext: modelContext)
            try detectLocalChanges(modelContext: modelContext)

            let remote = try await fetchRemote(database: database, zoneID: zoneID)
            let pulled = try pull(remote: remote, modelContext: modelContext)
            try modelContext.save()

            let pushed = try await push(
                membership: membership,
                remote: remote,
                database: database,
                zoneID: zoneID,
                modelContext: modelContext
            )

            try modelContext.save()
            persistFingerprints()

            let result = FamilySyncResult(pushed: pushed, pulled: pulled.applied, removedLocally: pulled.removed)
            lastSyncAt = Date()
            lastResultSummary = "Synced · ↑\(result.pushed) ↓\(result.pulled)"
                + (result.removedLocally > 0 ? " · removed \(result.removedLocally)" : "")
            return result
        } catch {
            persistFingerprints()
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Zone helpers

    private func database(for membership: FamilyMembership) -> CKDatabase {
        membership.isOwner ? privateDB : sharedDB
    }

    private func zoneID(for membership: FamilyMembership) -> CKRecordZone.ID {
        if membership.isOwner {
            CKRecordZone.ID(zoneName: membership.zoneName, ownerName: CKCurrentUserDefaultName)
        } else {
            CKRecordZone.ID(zoneName: membership.zoneName, ownerName: membership.zoneOwnerName)
        }
    }

    // MARK: - Local change detection

    private func fingerprint(of model: any FamilySyncable) -> String {
        var fields = SyncFields()
        model.encodeSyncFields(into: &fields)
        return fields.fingerprint
    }

    /// Before fingerprints existed, `cloudSynced` marked what had been uploaded. Adopt those once.
    private func seedFingerprintsIfNeeded(modelContext: ModelContext) throws {
        let key = "FamilySync.fingerprintsSeeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for entity in entities {
            for model in try entity.fetchLocal(modelContext) where model.cloudSynced {
                syncedFingerprints[entity.recordName(for: model.id)] = fingerprint(of: model)
            }
        }
        persistFingerprints()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Stamps edited records as modified now and queues deletions for synced records that are gone locally.
    private func detectLocalChanges(modelContext: ModelContext) throws {
        for entity in entities {
            let locals = try entity.fetchLocal(modelContext)
            var localNames = Set<String>()
            for model in locals {
                let name = entity.recordName(for: model.id)
                localNames.insert(name)
                if let known = syncedFingerprints[name], known != fingerprint(of: model) {
                    model.modifiedAt = Date()
                }
            }
            let namePrefix = "\(entity.prefix)."
            for name in syncedFingerprints.keys where name.hasPrefix(namePrefix) && !localNames.contains(name) {
                pendingDeletionRecordNames.insert(name)
                syncedFingerprints[name] = nil
            }
        }
        persistPendingDeletions()
    }

    // MARK: - Pull

    private struct PullOutcome {
        var applied: Int
        var removed: Int
    }

    /// Remote records keyed by record type, then by model ID.
    private typealias RemoteSnapshot = [String: [UUID: CKRecord]]

    private func fetchRemote(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> RemoteSnapshot {
        var snapshot: RemoteSnapshot = [:]
        for entity in entities {
            let records = try await fetchAll(recordType: entity.recordType, database: database, zoneID: zoneID)
            snapshot[entity.recordType] = Dictionary(
                records.compactMap { record in uuid(from: record, prefix: entity.prefix).map { ($0, record) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return snapshot
    }

    private func pull(remote: RemoteSnapshot, modelContext: ModelContext) throws -> PullOutcome {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let lookup = SyncLookup(modelContext: modelContext)
        var applied = 0
        var removed = 0

        for entity in entities {
            lookup.invalidate()
            let records = remote[entity.recordType] ?? [:]
            var locals = Dictionary(
                try entity.fetchLocal(modelContext).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for (id, record) in records {
                let name = entity.recordName(for: id)
                // Deleted here but not yet pushed — don't resurrect it.
                guard !pendingDeletionRecordNames.contains(name) else { continue }
                let remoteModified = (record["modifiedAt"] as? Date) ?? .distantPast

                let model: any FamilySyncable
                if let local = locals[id] {
                    guard remoteModified > local.modifiedAt else { continue }
                    model = local
                } else {
                    model = entity.makeNew()
                    model.id = id
                    modelContext.insert(model)
                    locals[id] = model
                }
                model.applySyncFields(from: SyncRecordReader(record: record), lookup: lookup)
                model.createdAt = (record["createdAt"] as? Date) ?? model.createdAt
                model.modifiedAt = remoteModified
                model.cloudSynced = true
                syncedFingerprints[name] = fingerprint(of: model)
                applied += 1
            }

            // Synced before but gone from the zone: another member deleted it.
            for (id, model) in locals where records[id] == nil {
                let name = entity.recordName(for: id)
                guard syncedFingerprints[name] != nil else { continue }
                modelContext.delete(model)
                syncedFingerprints[name] = nil
                removed += 1
            }
        }

        return PullOutcome(applied: applied, removed: removed)
    }

    // MARK: - Push

    private func push(
        membership: FamilyMembership,
        remote: RemoteSnapshot,
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        modelContext: ModelContext
    ) async throws -> Int {
        var toSave: [CKRecord] = []
        var pushed: [(model: any FamilySyncable, name: String, fingerprint: String)] = []
        var tempFiles: [URL] = []
        defer {
            for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        }

        for entity in entities {
            let remoteRecords = remote[entity.recordType] ?? [:]
            for model in try entity.fetchLocal(modelContext) {
                let name = entity.recordName(for: model.id)
                let existing = remoteRecords[model.id]
                guard shouldUpload(
                    createdAt: model.createdAt,
                    isKnown: syncedFingerprints[name] != nil,
                    modifiedAt: model.modifiedAt,
                    remoteModified: (existing?["modifiedAt"] as? Date) ?? .distantPast,
                    existsRemotely: existing != nil,
                    membership: membership
                ) else { continue }

                let record = existing ?? CKRecord(
                    recordType: entity.recordType,
                    recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
                )
                var fields = SyncFields()
                model.encodeSyncFields(into: &fields)
                record["id"] = model.id.uuidString as CKRecordValue
                record["createdAt"] = model.createdAt as CKRecordValue
                record["modifiedAt"] = model.modifiedAt as CKRecordValue
                try fields.write(into: record, assetName: name, tempFiles: &tempFiles)
                toSave.append(record)
                pushed.append((model, name, fields.fingerprint))
            }
        }

        // Push explicit local deletions only (never delete remotes just because this device is empty).
        let toDelete = pendingDeletionRecordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

        guard !toSave.isEmpty || !toDelete.isEmpty else { return 0 }

        let savedCount = try await modifyRecords(toSave: toSave, toDelete: toDelete, database: database)
        for item in pushed {
            item.model.cloudSynced = true
            syncedFingerprints[item.name] = item.fingerprint
        }
        if !toDelete.isEmpty {
            for id in toDelete {
                pendingDeletionRecordNames.remove(id.recordName)
            }
            persistPendingDeletions()
        }
        return savedCount
    }

    /// Owners seed a new hub with local data. Joiners only upload items created after joining
    /// (or updates to records that already exist in the shared zone).
    private func shouldUpload(
        createdAt: Date,
        isKnown: Bool,
        modifiedAt: Date,
        remoteModified: Date,
        existsRemotely: Bool,
        membership: FamilyMembership
    ) -> Bool {
        if isKnown && modifiedAt <= remoteModified { return false }
        if existsRemotely { return true }
        if membership.isOwner { return true }
        return createdAt >= membership.joinedAt
    }

    // MARK: - CloudKit IO

    private func fetchAll(recordType: String, database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        do {
            return try await fetchAllThrowing(recordType: recordType, database: database, zoneID: zoneID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .invalidArguments {
            // Record type not created in this environment yet — treat as empty, not as "delete everything".
            return []
        }
    }

    private func fetchAllThrowing(recordType: String, database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        while true {
            let page: (records: [CKRecord], cursor: CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { continuation in
                let operation: CKQueryOperation
                if let cursor {
                    operation = CKQueryOperation(cursor: cursor)
                } else {
                    let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                    operation = CKQueryOperation(query: query)
                }
                operation.zoneID = zoneID
                operation.resultsLimit = 100
                var pageRecords: [CKRecord] = []
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        pageRecords.append(record)
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .success(let nextCursor):
                        continuation.resume(returning: (pageRecords, nextCursor))
                    }
                }
                database.add(operation)
            }
            collected.append(contentsOf: page.records)
            guard let next = page.cursor else { break }
            cursor = next
        }

        return collected
    }

    private func modifyRecords(toSave: [CKRecord], toDelete: [CKRecord.ID], database: CKDatabase) async throws -> Int {
        let saveBatches = stride(from: 0, to: toSave.count, by: 50).map { Array(toSave[$0..<min($0 + 50, toSave.count)]) }
        let deleteBatches = stride(from: 0, to: toDelete.count, by: 50).map { Array(toDelete[$0..<min($0 + 50, toDelete.count)]) }
        let batchCount = max(saveBatches.count, deleteBatches.count, 1)
        var saved = 0

        for index in 0..<batchCount {
            let saves = index < saveBatches.count ? saveBatches[index] : []
            let deletes = index < deleteBatches.count ? deleteBatches[index] : []
            if saves.isEmpty && deletes.isEmpty { continue }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: saves.isEmpty ? nil : saves, recordIDsToDelete: deletes.isEmpty ? nil : deletes)
                operation.savePolicy = .changedKeys
                operation.isAtomic = false
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
            saved += saves.count
        }
        return saved
    }

    private func uuid(from record: CKRecord, prefix: String) -> UUID? {
        let name = record.recordID.recordName
        if name.hasPrefix("\(prefix).") {
            return UUID(uuidString: String(name.dropFirst(prefix.count + 1)))
        }
        return (record["id"] as? String).flatMap(UUID.init)
    }
}
