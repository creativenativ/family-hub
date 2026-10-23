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

@MainActor
@Observable
final class FamilySyncService {
    static let shared = FamilySyncService()

    private let container = CKContainer(identifier: FamilyCloudService.containerIdentifier)

    private let memberType = "SharedFamilyMember"
    private let eventType = "SharedCalendarEvent"
    private let choreType = "SharedChore"
    private let recipeType = "SharedRecipe"

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

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func noteLocalDeletion(prefix: String, id: UUID) {
        pendingDeletionRecordNames.insert("\(prefix).\(id.uuidString)")
        persistPendingDeletions()
    }

    private func persistPendingDeletions() {
        UserDefaults.standard.set(Array(pendingDeletionRecordNames), forKey: "FamilySync.pendingDeletions")
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

    /// Call when leaving a hub so a later empty-zone sync cannot wipe local calendar data.
    func detachLocalDataFromFamily(modelContext: ModelContext) throws {
        for member in try modelContext.fetch(FetchDescriptor<FamilyMember>()) {
            member.cloudSynced = false
        }
        for event in try modelContext.fetch(FetchDescriptor<CalendarEvent>()) {
            event.cloudSynced = false
        }
        for chore in try modelContext.fetch(FetchDescriptor<Chore>()) {
            chore.cloudSynced = false
        }
        for recipe in try modelContext.fetch(FetchDescriptor<Recipe>()) {
            recipe.cloudSynced = false
        }
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

            let pulled = try await pull(database: database, zoneID: zoneID, modelContext: modelContext)
            let pushed = try await push(
                membership: membership,
                database: database,
                zoneID: zoneID,
                modelContext: modelContext
            )

            try modelContext.save()

            let result = FamilySyncResult(pushed: pushed, pulled: pulled.applied, removedLocally: pulled.removed)
            lastSyncAt = Date()
            lastResultSummary = "Synced · ↑\(result.pushed) ↓\(result.pulled)"
                + (result.removedLocally > 0 ? " · removed \(result.removedLocally)" : "")
            return result
        } catch {
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

    private func recordID(prefix: String, id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(prefix).\(id.uuidString)", zoneID: zoneID)
    }

    // MARK: - Pull

    private struct PullOutcome {
        var applied: Int
        var removed: Int
    }

    private func pull(
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        modelContext: ModelContext
    ) async throws -> PullOutcome {
        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let remoteMembers = try await fetchAll(recordType: memberType, database: database, zoneID: zoneID)
        let remoteEvents = try await fetchAll(recordType: eventType, database: database, zoneID: zoneID)
        let remoteChores = try await fetchAll(recordType: choreType, database: database, zoneID: zoneID)
        let remoteRecipes = try await fetchAll(recordType: recipeType, database: database, zoneID: zoneID)

        var applied = 0
        applied += try applyMembers(remoteMembers, modelContext: modelContext)
        applied += try applyEvents(remoteEvents, modelContext: modelContext)
        applied += try applyChores(remoteChores, modelContext: modelContext)
        applied += try applyRecipes(remoteRecipes, modelContext: modelContext)

        let removed = try removeOrphans(
            remoteMembers: remoteMembers,
            remoteEvents: remoteEvents,
            remoteChores: remoteChores,
            remoteRecipes: remoteRecipes,
            modelContext: modelContext
        )

        return PullOutcome(applied: applied, removed: removed)
    }

    private func applyMembers(_ records: [CKRecord], modelContext: ModelContext) throws -> Int {
        let locals = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<FamilyMember>())).map { ($0.id, $0) })
        var applied = 0
        for record in records {
            guard let id = uuid(from: record, prefix: "member") ?? (record["id"] as? String).flatMap(UUID.init) else { continue }
            let remoteModified = (record["modifiedAt"] as? Date) ?? .distantPast
            if let local = locals[id] {
                guard remoteModified > local.modifiedAt else { continue }
                apply(record, to: local)
                local.cloudSynced = true
                applied += 1
            } else {
                let member = FamilyMember(name: (record["name"] as? String) ?? "Member")
                member.id = id
                apply(record, to: member)
                member.cloudSynced = true
                modelContext.insert(member)
                applied += 1
            }
        }
        return applied
    }

    private func apply(_ record: CKRecord, to member: FamilyMember) {
        member.name = (record["name"] as? String) ?? member.name
        member.colorHex = (record["colorHex"] as? String) ?? member.colorHex
        member.inviteEmail = (record["inviteEmail"] as? String) ?? member.inviteEmail
        member.invitePhone = (record["invitePhone"] as? String) ?? member.invitePhone
        member.createdAt = (record["createdAt"] as? Date) ?? member.createdAt
        member.modifiedAt = (record["modifiedAt"] as? Date) ?? member.modifiedAt
        if let asset = record["profileImage"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            member.profileImageData = data
        } else if record["profileImage"] == nil {
            // Keep existing local image if remote omitted asset due to size; only clear when explicitly empty flag set
            if (record["hasProfileImage"] as? Int) == 0 {
                member.profileImageData = nil
            }
        }
    }

    private func applyEvents(_ records: [CKRecord], modelContext: ModelContext) throws -> Int {
        let locals = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<CalendarEvent>())).map { ($0.id, $0) })
        let members = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<FamilyMember>())).map { ($0.id, $0) })
        var applied = 0
        for record in records {
            guard let id = uuid(from: record, prefix: "event") ?? (record["id"] as? String).flatMap(UUID.init) else { continue }
            let remoteModified = (record["modifiedAt"] as? Date) ?? .distantPast
            let event: CalendarEvent
            if let local = locals[id] {
                guard remoteModified > local.modifiedAt else { continue }
                event = local
            } else {
                event = CalendarEvent(
                    title: (record["title"] as? String) ?? "Event",
                    startDate: (record["startDate"] as? Date) ?? Date(),
                    endDate: (record["endDate"] as? Date) ?? Date()
                )
                event.id = id
                modelContext.insert(event)
            }
            event.title = (record["title"] as? String) ?? event.title
            event.notes = (record["notes"] as? String) ?? ""
            event.startDate = (record["startDate"] as? Date) ?? event.startDate
            event.endDate = (record["endDate"] as? Date) ?? event.endDate
            event.isAllDay = (record["isAllDay"] as? Int).map { $0 != 0 } ?? event.isAllDay
            event.location = (record["location"] as? String) ?? ""
            event.createdAt = (record["createdAt"] as? Date) ?? event.createdAt
            event.modifiedAt = remoteModified
            event.notificationsEnabled = (record["notificationsEnabled"] as? Int).map { $0 != 0 } ?? event.notificationsEnabled
            if let memberID = (record["assignedMemberID"] as? String).flatMap(UUID.init) {
                event.assignedMember = members[memberID]
            } else {
                event.assignedMember = nil
            }
            event.cloudSynced = true
            applied += 1
        }
        return applied
    }

    private func applyChores(_ records: [CKRecord], modelContext: ModelContext) throws -> Int {
        let locals = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<Chore>())).map { ($0.id, $0) })
        let members = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<FamilyMember>())).map { ($0.id, $0) })
        var applied = 0
        for record in records {
            guard let id = uuid(from: record, prefix: "chore") ?? (record["id"] as? String).flatMap(UUID.init) else { continue }
            let remoteModified = (record["modifiedAt"] as? Date) ?? .distantPast
            let chore: Chore
            if let local = locals[id] {
                guard remoteModified > local.modifiedAt else { continue }
                chore = local
            } else {
                chore = Chore(title: (record["title"] as? String) ?? "Chore")
                chore.id = id
                modelContext.insert(chore)
            }
            chore.title = (record["title"] as? String) ?? chore.title
            chore.notes = (record["notes"] as? String) ?? ""
            chore.dueDate = (record["dueDate"] as? Date) ?? chore.dueDate
            chore.frequencyRaw = (record["frequencyRaw"] as? String) ?? chore.frequencyRaw
            chore.isCompleted = (record["isCompleted"] as? Int).map { $0 != 0 } ?? chore.isCompleted
            chore.completedAt = record["completedAt"] as? Date
            chore.remindersEnabled = (record["remindersEnabled"] as? Int).map { $0 != 0 } ?? chore.remindersEnabled
            chore.createdAt = (record["createdAt"] as? Date) ?? chore.createdAt
            chore.modifiedAt = remoteModified
            if let data = record["componentsData"] as? Data {
                chore.componentsData = data
            } else if let asset = record["componentsData"] as? CKAsset, let url = asset.fileURL,
                      let data = try? Data(contentsOf: url) {
                chore.componentsData = data
            }
            if let memberID = (record["assignedMemberID"] as? String).flatMap(UUID.init) {
                chore.assignedMember = members[memberID]
            } else {
                chore.assignedMember = nil
            }
            chore.cloudSynced = true
            applied += 1
        }
        return applied
    }

    private func applyRecipes(_ records: [CKRecord], modelContext: ModelContext) throws -> Int {
        let locals = Dictionary(uniqueKeysWithValues: (try modelContext.fetch(FetchDescriptor<Recipe>())).map { ($0.id, $0) })
        var applied = 0
        for record in records {
            guard let id = uuid(from: record, prefix: "recipe") ?? (record["id"] as? String).flatMap(UUID.init) else { continue }
            let remoteModified = (record["modifiedAt"] as? Date) ?? .distantPast
            let recipe: Recipe
            if let local = locals[id] {
                guard remoteModified > local.modifiedAt else { continue }
                recipe = local
            } else {
                recipe = Recipe(name: (record["name"] as? String) ?? "Recipe")
                recipe.id = id
                modelContext.insert(recipe)
            }
            recipe.name = (record["name"] as? String) ?? recipe.name
            recipe.summary = (record["summary"] as? String) ?? ""
            recipe.instructions = (record["instructions"] as? String) ?? ""
            recipe.sourceURL = (record["sourceURL"] as? String) ?? ""
            recipe.imageURL = (record["imageURL"] as? String) ?? ""
            recipe.servings = (record["servings"] as? Int) ?? recipe.servings
            recipe.externalID = (record["externalID"] as? String) ?? ""
            if let data = record["ingredientsData"] as? Data {
                recipe.ingredientsData = data
            } else if let asset = record["ingredientsData"] as? CKAsset, let url = asset.fileURL,
                      let data = try? Data(contentsOf: url) {
                recipe.ingredientsData = data
            }
            if let asset = record["image"] as? CKAsset, let url = asset.fileURL,
               let data = try? Data(contentsOf: url) {
                recipe.imageData = data
            } else if (record["hasImage"] as? Int) == 0 {
                recipe.imageData = nil
            }
            recipe.createdAt = (record["createdAt"] as? Date) ?? recipe.createdAt
            recipe.modifiedAt = remoteModified
            recipe.cloudSynced = true
            applied += 1
        }
        return applied
    }

    private func removeOrphans(
        remoteMembers: [CKRecord],
        remoteEvents: [CKRecord],
        remoteChores: [CKRecord],
        remoteRecipes: [CKRecord],
        modelContext: ModelContext
    ) throws -> Int {
        let remoteMemberIDs = Set(remoteMembers.compactMap { uuid(from: $0, prefix: "member") })
        let remoteEventIDs = Set(remoteEvents.compactMap { uuid(from: $0, prefix: "event") })
        let remoteChoreIDs = Set(remoteChores.compactMap { uuid(from: $0, prefix: "chore") })
        let remoteRecipeIDs = Set(remoteRecipes.compactMap { uuid(from: $0, prefix: "recipe") })

        var removed = 0
        for member in try modelContext.fetch(FetchDescriptor<FamilyMember>()) where member.cloudSynced && !remoteMemberIDs.contains(member.id) {
            modelContext.delete(member)
            removed += 1
        }
        for event in try modelContext.fetch(FetchDescriptor<CalendarEvent>()) where event.cloudSynced && !remoteEventIDs.contains(event.id) {
            modelContext.delete(event)
            removed += 1
        }
        for chore in try modelContext.fetch(FetchDescriptor<Chore>()) where chore.cloudSynced && !remoteChoreIDs.contains(chore.id) {
            modelContext.delete(chore)
            removed += 1
        }
        for recipe in try modelContext.fetch(FetchDescriptor<Recipe>()) where recipe.cloudSynced && !remoteRecipeIDs.contains(recipe.id) {
            modelContext.delete(recipe)
            removed += 1
        }
        return removed
    }

    // MARK: - Push

    private func push(
        membership: FamilyMembership,
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        modelContext: ModelContext
    ) async throws -> Int {
        let remoteMembers = Dictionary(uniqueKeysWithValues: try await fetchAll(recordType: memberType, database: database, zoneID: zoneID).compactMap { record -> (UUID, CKRecord)? in
            guard let id = uuid(from: record, prefix: "member") else { return nil }
            return (id, record)
        })
        let remoteEvents = Dictionary(uniqueKeysWithValues: try await fetchAll(recordType: eventType, database: database, zoneID: zoneID).compactMap { record -> (UUID, CKRecord)? in
            guard let id = uuid(from: record, prefix: "event") else { return nil }
            return (id, record)
        })
        let remoteChores = Dictionary(uniqueKeysWithValues: try await fetchAll(recordType: choreType, database: database, zoneID: zoneID).compactMap { record -> (UUID, CKRecord)? in
            guard let id = uuid(from: record, prefix: "chore") else { return nil }
            return (id, record)
        })
        let remoteRecipes = Dictionary(uniqueKeysWithValues: try await fetchAll(recordType: recipeType, database: database, zoneID: zoneID).compactMap { record -> (UUID, CKRecord)? in
            guard let id = uuid(from: record, prefix: "recipe") else { return nil }
            return (id, record)
        })

        var toSave: [CKRecord] = []
        var pushedMembers: [FamilyMember] = []
        var pushedEvents: [CalendarEvent] = []
        var pushedChores: [Chore] = []
        var pushedRecipes: [Recipe] = []
        var tempFiles: [URL] = []
        defer {
            for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        }

        for member in try modelContext.fetch(FetchDescriptor<FamilyMember>()) {
            let existsRemotely = remoteMembers[member.id] != nil
            guard shouldUpload(
                createdAt: member.createdAt,
                cloudSynced: member.cloudSynced,
                modifiedAt: member.modifiedAt,
                remoteModified: (remoteMembers[member.id]?["modifiedAt"] as? Date) ?? .distantPast,
                existsRemotely: existsRemotely,
                membership: membership
            ) else { continue }
            let record = remoteMembers[member.id] ?? CKRecord(
                recordType: memberType,
                recordID: recordID(prefix: "member", id: member.id, zoneID: zoneID)
            )
            try encode(member: member, into: record, tempFiles: &tempFiles)
            toSave.append(record)
            pushedMembers.append(member)
        }

        for event in try modelContext.fetch(FetchDescriptor<CalendarEvent>()) {
            let existsRemotely = remoteEvents[event.id] != nil
            guard shouldUpload(
                createdAt: event.createdAt,
                cloudSynced: event.cloudSynced,
                modifiedAt: event.modifiedAt,
                remoteModified: (remoteEvents[event.id]?["modifiedAt"] as? Date) ?? .distantPast,
                existsRemotely: existsRemotely,
                membership: membership
            ) else { continue }
            let record = remoteEvents[event.id] ?? CKRecord(
                recordType: eventType,
                recordID: recordID(prefix: "event", id: event.id, zoneID: zoneID)
            )
            encode(event: event, into: record)
            toSave.append(record)
            pushedEvents.append(event)
        }

        for chore in try modelContext.fetch(FetchDescriptor<Chore>()) {
            let existsRemotely = remoteChores[chore.id] != nil
            guard shouldUpload(
                createdAt: chore.createdAt,
                cloudSynced: chore.cloudSynced,
                modifiedAt: chore.modifiedAt,
                remoteModified: (remoteChores[chore.id]?["modifiedAt"] as? Date) ?? .distantPast,
                existsRemotely: existsRemotely,
                membership: membership
            ) else { continue }
            let record = remoteChores[chore.id] ?? CKRecord(
                recordType: choreType,
                recordID: recordID(prefix: "chore", id: chore.id, zoneID: zoneID)
            )
            try encode(chore: chore, into: record, tempFiles: &tempFiles)
            toSave.append(record)
            pushedChores.append(chore)
        }

        for recipe in try modelContext.fetch(FetchDescriptor<Recipe>()) {
            let existsRemotely = remoteRecipes[recipe.id] != nil
            guard shouldUpload(
                createdAt: recipe.createdAt,
                cloudSynced: recipe.cloudSynced,
                modifiedAt: recipe.modifiedAt,
                remoteModified: (remoteRecipes[recipe.id]?["modifiedAt"] as? Date) ?? .distantPast,
                existsRemotely: existsRemotely,
                membership: membership
            ) else { continue }
            let record = remoteRecipes[recipe.id] ?? CKRecord(
                recordType: recipeType,
                recordID: recordID(prefix: "recipe", id: recipe.id, zoneID: zoneID)
            )
            try encode(recipe: recipe, into: record, tempFiles: &tempFiles)
            toSave.append(record)
            pushedRecipes.append(recipe)
        }

        // Push explicit local deletions only (never delete remotes just because this device is empty).
        var toDelete: [CKRecord.ID] = []
        for recordName in pendingDeletionRecordNames {
            toDelete.append(CKRecord.ID(recordName: recordName, zoneID: zoneID))
        }

        guard !toSave.isEmpty || !toDelete.isEmpty else { return 0 }

        let savedCount = try await modifyRecords(toSave: toSave, toDelete: toDelete, database: database)
        for member in pushedMembers { member.cloudSynced = true }
        for event in pushedEvents { event.cloudSynced = true }
        for chore in pushedChores { chore.cloudSynced = true }
        for recipe in pushedRecipes { recipe.cloudSynced = true }
        if !toDelete.isEmpty {
            for id in toDelete {
                pendingDeletionRecordNames.remove(id.recordName)
            }
            persistPendingDeletions()
        }
        return savedCount
    }

    private func encode(member: FamilyMember, into record: CKRecord, tempFiles: inout [URL]) throws {
        record["id"] = member.id.uuidString as CKRecordValue
        record["name"] = member.name as CKRecordValue
        record["colorHex"] = member.colorHex as CKRecordValue
        record["inviteEmail"] = member.inviteEmail as CKRecordValue
        record["invitePhone"] = member.invitePhone as CKRecordValue
        record["createdAt"] = member.createdAt as CKRecordValue
        record["modifiedAt"] = member.modifiedAt as CKRecordValue
        if let data = member.profileImageData, !data.isEmpty {
            record["hasProfileImage"] = 1 as CKRecordValue
            record["profileImage"] = try asset(from: data, name: "member-\(member.id.uuidString).jpg", tempFiles: &tempFiles)
        } else {
            record["hasProfileImage"] = 0 as CKRecordValue
            record["profileImage"] = nil
        }
    }

    private func encode(event: CalendarEvent, into record: CKRecord) {
        record["id"] = event.id.uuidString as CKRecordValue
        record["title"] = event.title as CKRecordValue
        record["notes"] = event.notes as CKRecordValue
        record["startDate"] = event.startDate as CKRecordValue
        record["endDate"] = event.endDate as CKRecordValue
        record["isAllDay"] = (event.isAllDay ? 1 : 0) as CKRecordValue
        record["location"] = event.location as CKRecordValue
        record["createdAt"] = event.createdAt as CKRecordValue
        record["modifiedAt"] = event.modifiedAt as CKRecordValue
        record["notificationsEnabled"] = (event.notificationsEnabled ? 1 : 0) as CKRecordValue
        if let memberID = event.assignedMember?.id.uuidString {
            record["assignedMemberID"] = memberID as CKRecordValue
        } else {
            record["assignedMemberID"] = nil
        }
    }

    /// Owners seed a new hub with local data. Joiners only upload items created after joining
    /// (or updates to records that already exist in the shared zone).
    private func shouldUpload(
        createdAt: Date,
        cloudSynced: Bool,
        modifiedAt: Date,
        remoteModified: Date,
        existsRemotely: Bool,
        membership: FamilyMembership
    ) -> Bool {
        if cloudSynced && modifiedAt <= remoteModified { return false }
        if existsRemotely { return true }
        if membership.isOwner { return true }
        return createdAt >= membership.joinedAt
    }

    private func encode(chore: Chore, into record: CKRecord, tempFiles: inout [URL]) throws {
        record["id"] = chore.id.uuidString as CKRecordValue
        record["title"] = chore.title as CKRecordValue
        record["notes"] = chore.notes as CKRecordValue
        record["dueDate"] = chore.dueDate as CKRecordValue
        record["frequencyRaw"] = chore.frequencyRaw as CKRecordValue
        record["isCompleted"] = (chore.isCompleted ? 1 : 0) as CKRecordValue
        if let completedAt = chore.completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        } else {
            record["completedAt"] = nil
        }
        record["remindersEnabled"] = (chore.remindersEnabled ? 1 : 0) as CKRecordValue
        record["createdAt"] = chore.createdAt as CKRecordValue
        record["modifiedAt"] = chore.modifiedAt as CKRecordValue
        if chore.componentsData.count < 900_000 {
            record["componentsData"] = chore.componentsData as CKRecordValue
        } else {
            record["componentsData"] = try asset(
                from: chore.componentsData,
                name: "chore-components-\(chore.id.uuidString).bin",
                tempFiles: &tempFiles
            )
        }
        if let memberID = chore.assignedMember?.id.uuidString {
            record["assignedMemberID"] = memberID as CKRecordValue
        } else {
            record["assignedMemberID"] = nil
        }
    }

    private func encode(recipe: Recipe, into record: CKRecord, tempFiles: inout [URL]) throws {
        record["id"] = recipe.id.uuidString as CKRecordValue
        record["name"] = recipe.name as CKRecordValue
        record["summary"] = recipe.summary as CKRecordValue
        record["instructions"] = recipe.instructions as CKRecordValue
        record["sourceURL"] = recipe.sourceURL as CKRecordValue
        record["imageURL"] = recipe.imageURL as CKRecordValue
        record["servings"] = recipe.servings as CKRecordValue
        record["externalID"] = recipe.externalID as CKRecordValue
        record["createdAt"] = recipe.createdAt as CKRecordValue
        record["modifiedAt"] = recipe.modifiedAt as CKRecordValue
        if recipe.ingredientsData.count < 900_000 {
            record["ingredientsData"] = recipe.ingredientsData as CKRecordValue
        } else {
            record["ingredientsData"] = try asset(from: recipe.ingredientsData, name: "ingredients-\(recipe.id.uuidString).bin", tempFiles: &tempFiles)
        }
        if let data = recipe.imageData, !data.isEmpty {
            record["hasImage"] = 1 as CKRecordValue
            record["image"] = try asset(from: data, name: "recipe-\(recipe.id.uuidString).jpg", tempFiles: &tempFiles)
        } else {
            record["hasImage"] = 0 as CKRecordValue
            record["image"] = nil
        }
    }

    private func asset(from data: Data, name: String, tempFiles: inout [URL]) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        tempFiles.append(url)
        return CKAsset(fileURL: url)
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
