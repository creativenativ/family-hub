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
    /// New or changed records of this type count as tribe activity (unread badges).
    var tracksActivity = false

    static func of<T: FamilySyncable>(_ type: T.Type) -> SyncEntity {
        SyncEntity(
            recordType: T.syncRecordType,
            prefix: T.syncPrefix,
            fetchLocal: { try $0.fetch(FetchDescriptor<T>()) },
            makeNew: { T.makeForSync() }
        )
    }

    /// Calendar events belonging to one tribe calendar ("" = home).
    static func events(zoneKey: String) -> SyncEntity {
        SyncEntity(
            recordType: CalendarEvent.syncRecordType,
            prefix: CalendarEvent.syncPrefix,
            fetchLocal: { context in
                try context.fetch(FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate { $0.tribeZoneName == zoneKey }
                ))
            },
            makeNew: {
                let event = CalendarEvent.makeForSync()
                event.tribeZoneName = zoneKey
                return event
            },
            tracksActivity: true
        )
    }

    func recordName(for id: UUID) -> String {
        "\(prefix).\(id.uuidString)"
    }
}

/// Per-tribe sync bookkeeping, persisted in UserDefaults.
private struct ScopeState {
    /// Record name → content fingerprint as of the last time this device synced it.
    /// Lets sync notice local edits and deletions without every screen having to report them.
    var fingerprints: [String: String]
    var pendingDeletions: Set<String>
}

@MainActor
@Observable
final class FamilySyncService {
    static let shared = FamilySyncService()

    private let container = CKContainer(identifier: FamilyCloudService.containerIdentifier)

    /// Home tribe: everything. Order matters: members first so relationships resolve,
    /// budget items before their expenses.
    private let homeEntities: [SyncEntity] = [
        .of(FamilyMember.self),
        .events(zoneKey: ""),
        .of(Chore.self),
        .of(BoardNote.self),
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
    /// Latest sync error per tribe zone name, for the tribe detail screen.
    var tribeErrors: [String: String] = [:]
    private var isApplyingRemote = false
    private var needsResync = false
    private var pendingSyncTask: Task<Void, Never>?
    private var states: [String: ScopeState] = [:]

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // MARK: - Scope state

    /// Home keeps the original UserDefaults keys so existing installs carry their history over.
    private func defaultsKeys(for storageKey: String) -> (fingerprints: String, deletions: String) {
        storageKey.isEmpty
            ? ("FamilySync.fingerprints", "FamilySync.pendingDeletions")
            : ("FamilySync.fingerprints.\(storageKey)", "FamilySync.pendingDeletions.\(storageKey)")
    }

    private func state(for storageKey: String) -> ScopeState {
        if let state = states[storageKey] { return state }
        let keys = defaultsKeys(for: storageKey)
        let state = ScopeState(
            fingerprints: (UserDefaults.standard.dictionary(forKey: keys.fingerprints) as? [String: String]) ?? [:],
            pendingDeletions: Set(UserDefaults.standard.stringArray(forKey: keys.deletions) ?? [])
        )
        states[storageKey] = state
        return state
    }

    private func persist(_ state: ScopeState, for storageKey: String) {
        states[storageKey] = state
        let keys = defaultsKeys(for: storageKey)
        UserDefaults.standard.set(state.fingerprints, forKey: keys.fingerprints)
        UserDefaults.standard.set(Array(state.pendingDeletions), forKey: keys.deletions)
    }

    private func clearState(for storageKey: String) {
        persist(ScopeState(fingerprints: [:], pendingDeletions: []), for: storageKey)
    }

    func noteLocalDeletion(prefix: String, id: UUID) {
        // Sync also detects deletions on its own; this just routes an explicit one to its tribe.
        let name = "\(prefix).\(id.uuidString)"
        for (key, var state) in states where state.fingerprints[name] != nil {
            state.pendingDeletions.insert(name)
            persist(state, for: key)
        }
    }

    // MARK: - Public

    func scheduleSync(modelContext: ModelContext, delayNanoseconds: UInt64 = 1_500_000_000) {
        if isApplyingRemote || isSyncing {
            needsResync = true
            return
        }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            _ = try? await self.syncAll(modelContext: modelContext)
        }
    }

    /// Call after the app's own context saves, so local edits reach the tribe quickly.
    /// Saves made by sync itself are ignored.
    func noteLocalSave(modelContext: ModelContext) {
        guard !isSyncing, !isApplyingRemote else { return }
        scheduleSync(modelContext: modelContext, delayNanoseconds: 3_000_000_000)
    }

    /// Call when leaving the home tribe so a later empty-zone sync cannot wipe local data.
    func detachLocalDataFromFamily(modelContext: ModelContext) throws {
        for entity in homeEntities {
            for model in try entity.fetchLocal(modelContext) {
                model.cloudSynced = false
            }
        }
        clearState(for: "")
        lastResultSummary = nil
        lastErrorMessage = nil
    }

    /// Call when leaving a non-home tribe calendar: its events go, and copies shared
    /// from it elsewhere stay as standalone events.
    func detachTribeCalendar(_ membership: FamilyMembership, modelContext: ModelContext) throws {
        let zoneKey = membership.zoneName
        for event in try modelContext.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.tribeZoneName == zoneKey }
        )) {
            modelContext.delete(event)
        }
        for copy in try modelContext.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.linkedSourceZoneName == zoneKey }
        )) {
            copy.linkedSourceEventID = nil
            copy.linkedSourceZoneName = ""
            copy.linkedSourceTribeName = ""
        }
        clearState(for: zoneKey)
        tribeErrors[zoneKey] = nil
    }

    /// Syncs every tribe this device belongs to, then refreshes events shared between them.
    @discardableResult
    func syncAll(modelContext: ModelContext) async throws -> FamilySyncResult {
        guard !isSyncing else {
            needsResync = true
            throw FamilySyncError.busy
        }
        let memberships = try modelContext.fetch(FetchDescriptor<FamilyMembership>())
        guard !memberships.isEmpty else { return FamilySyncResult(pushed: 0, pulled: 0, removedLocally: 0) }

        isSyncing = true
        lastErrorMessage = nil
        defer {
            isSyncing = false
            if needsResync {
                needsResync = false
                scheduleSync(modelContext: modelContext, delayNanoseconds: 500_000_000)
            }
        }

        var total = FamilySyncResult(pushed: 0, pulled: 0, removedLocally: 0)
        var syncedZones = Set<String>()
        var firstError: Error?

        // Other tribes first, so copies shared from them can refresh before home pushes.
        let ordered = FamilyMembership.extras(in: memberships) + memberships.filter(\.isHome)
        for membership in ordered {
            do {
                let result = try await sync(membership: membership, modelContext: modelContext)
                total.pushed += result.pushed
                total.pulled += result.pulled
                total.removedLocally += result.removedLocally
                syncedZones.insert(membership.zoneName)
                tribeErrors[membership.zoneName] = nil
            } catch {
                tribeErrors[membership.zoneName] = error.localizedDescription
                firstError = firstError ?? error
            }
        }

        if try refreshLinkedCopies(memberships: memberships, syncedZones: syncedZones, modelContext: modelContext) {
            // Updated copies live in tribes that may already have pushed this round.
            needsResync = true
        }
        try modelContext.save()

        lastSyncAt = Date()
        lastResultSummary = "Synced · ↑\(total.pushed) ↓\(total.pulled)"
            + (total.removedLocally > 0 ? " · removed \(total.removedLocally)" : "")
        if let firstError {
            lastErrorMessage = firstError.localizedDescription
            throw firstError
        }
        return total
    }

    // MARK: - One tribe

    private func sync(membership: FamilyMembership, modelContext: ModelContext) async throws -> FamilySyncResult {
        let entities = membership.isHome ? homeEntities : [.events(zoneKey: membership.zoneName)]
        let storageKey = membership.eventZoneKey
        var state = state(for: storageKey)
        defer { persist(state, for: storageKey) }

        let zoneID = zoneID(for: membership)
        let database = database(for: membership)
        let isFirstSync = state.fingerprints.isEmpty

        if membership.isHome {
            try seedFingerprintsIfNeeded(entities: entities, state: &state, modelContext: modelContext)
        }
        try detectLocalChanges(entities: entities, state: &state, modelContext: modelContext)

        let remote = try await fetchRemote(entities: entities, database: database, zoneID: zoneID)
        let pulled = try pull(
            entities: entities,
            remote: remote,
            state: &state,
            modelContext: modelContext
        )
        if pulled.activity > 0 {
            membership.lastActivityAt = Date()
            if !isFirstSync {
                membership.unreadCount += pulled.activity
            }
        }
        try modelContext.save()

        let pushed = try await push(
            entities: entities,
            membership: membership,
            remote: remote,
            state: &state,
            database: database,
            zoneID: zoneID,
            modelContext: modelContext
        )
        try modelContext.save()

        return FamilySyncResult(pushed: pushed, pulled: pulled.applied, removedLocally: pulled.removed)
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
    private func seedFingerprintsIfNeeded(
        entities: [SyncEntity],
        state: inout ScopeState,
        modelContext: ModelContext
    ) throws {
        let key = "FamilySync.fingerprintsSeeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for entity in entities {
            for model in try entity.fetchLocal(modelContext) where model.cloudSynced {
                state.fingerprints[entity.recordName(for: model.id)] = fingerprint(of: model)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Stamps edited records as modified now and queues deletions for synced records that are gone locally.
    private func detectLocalChanges(
        entities: [SyncEntity],
        state: inout ScopeState,
        modelContext: ModelContext
    ) throws {
        for entity in entities {
            let locals = try entity.fetchLocal(modelContext)
            var localNames = Set<String>()
            for model in locals {
                let name = entity.recordName(for: model.id)
                localNames.insert(name)
                if let known = state.fingerprints[name], known != fingerprint(of: model) {
                    model.modifiedAt = Date()
                }
            }
            let namePrefix = "\(entity.prefix)."
            for name in state.fingerprints.keys where name.hasPrefix(namePrefix) && !localNames.contains(name) {
                state.pendingDeletions.insert(name)
                state.fingerprints[name] = nil
            }
        }
    }

    // MARK: - Pull

    private struct PullOutcome {
        var applied: Int
        var removed: Int
        var activity: Int
    }

    /// Remote records keyed by record type, then by model ID.
    private typealias RemoteSnapshot = [String: [UUID: CKRecord]]

    private func fetchRemote(
        entities: [SyncEntity],
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> RemoteSnapshot {
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

    private func pull(
        entities: [SyncEntity],
        remote: RemoteSnapshot,
        state: inout ScopeState,
        modelContext: ModelContext
    ) throws -> PullOutcome {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let lookup = SyncLookup(modelContext: modelContext)
        var outcome = PullOutcome(applied: 0, removed: 0, activity: 0)

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
                guard !state.pendingDeletions.contains(name) else { continue }
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
                state.fingerprints[name] = fingerprint(of: model)
                outcome.applied += 1
                if entity.tracksActivity { outcome.activity += 1 }
            }

            // Synced before but gone from the zone: another member deleted it.
            for (id, model) in locals where records[id] == nil {
                let name = entity.recordName(for: id)
                guard state.fingerprints[name] != nil else { continue }
                modelContext.delete(model)
                state.fingerprints[name] = nil
                outcome.removed += 1
            }
        }

        return outcome
    }

    // MARK: - Push

    private func push(
        entities: [SyncEntity],
        membership: FamilyMembership,
        remote: RemoteSnapshot,
        state: inout ScopeState,
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
                    isKnown: state.fingerprints[name] != nil,
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
        let toDelete = state.pendingDeletions.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

        guard !toSave.isEmpty || !toDelete.isEmpty else { return 0 }

        let savedCount = try await modifyRecords(toSave: toSave, toDelete: toDelete, database: database)
        for item in pushed {
            item.model.cloudSynced = true
            state.fingerprints[item.name] = item.fingerprint
        }
        for id in toDelete {
            state.pendingDeletions.remove(id.recordName)
        }
        return savedCount
    }

    /// Owners seed a new hub with local data. Joiners only upload items created after joining
    /// (or updates to records that already exist in the shared zone).
    /// Events in a non-home tribe were always created for that tribe, so they always upload.
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
        if membership.isOwner || !membership.isHome { return true }
        return createdAt >= membership.joinedAt
    }

    // MARK: - Linked copies

    /// Copies shared into another tribe follow their original. Returns true if any copy changed.
    private func refreshLinkedCopies(
        memberships: [FamilyMembership],
        syncedZones: Set<String>,
        modelContext: ModelContext
    ) throws -> Bool {
        let allEvents = try modelContext.fetch(FetchDescriptor<CalendarEvent>())
        let byID = Dictionary(allEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let myZones = Set(memberships.map(\.zoneName))
        var changed = false

        for copy in allEvents {
            guard let sourceID = copy.linkedSourceEventID else { continue }
            if let source = byID[sourceID] {
                changed = copy.adoptSchedule(of: source) || changed
            } else if myZones.contains(copy.linkedSourceZoneName),
                      syncedZones.contains(copy.linkedSourceZoneName) {
                // The original was deleted in a tribe this device just synced.
                modelContext.delete(copy)
                changed = true
            }
        }
        return changed
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
                        if Self.onlyMissingRecords(error) {
                            // Deleting something that's already gone is fine.
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                database.add(operation)
            }
            saved += saves.count
        }
        return saved
    }

    private nonisolated static func onlyMissingRecords(_ error: Error) -> Bool {
        guard let error = error as? CKError, error.code == .partialFailure,
              let partial = error.partialErrorsByItemID, !partial.isEmpty
        else { return false }
        return partial.values.allSatisfy { ($0 as? CKError)?.code == .unknownItem }
    }

    private func uuid(from record: CKRecord, prefix: String) -> UUID? {
        let name = record.recordID.recordName
        if name.hasPrefix("\(prefix).") {
            return UUID(uuidString: String(name.dropFirst(prefix.count + 1)))
        }
        return (record["id"] as? String).flatMap(UUID.init)
    }
}

extension CalendarEvent {
    /// Copies the schedule details of another event. Returns true if anything changed.
    @discardableResult
    func adoptSchedule(of source: CalendarEvent) -> Bool {
        guard title != source.title || notes != source.notes || location != source.location
            || startDate != source.startDate || endDate != source.endDate || isAllDay != source.isAllDay
        else { return false }
        title = source.title
        notes = source.notes
        location = source.location
        startDate = source.startDate
        endDate = source.endDate
        isAllDay = source.isAllDay
        return true
    }
}
