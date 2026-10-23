import CloudKit
import CryptoKit
import Foundation
import SwiftData

/// A SwiftData model that syncs into the shared tribe zone as one CloudKit record.
/// `id`, `createdAt` and `modifiedAt` are written by the sync engine; conformers only
/// describe their own content fields.
protocol FamilySyncable: PersistentModel {
    var id: UUID { get set }
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
    var cloudSynced: Bool { get set }

    static var syncRecordType: String { get }
    static var syncPrefix: String { get }

    /// A blank instance used when a record arrives from another tribe member.
    static func makeForSync() -> Self

    func encodeSyncFields(into fields: inout SyncFields)
    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup)
}

// MARK: - Field encoding

enum SyncValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case date(Date)
    /// Stored inline when small, as an asset when large.
    case data(Data)
    /// Always stored as a CKAsset (images, audio).
    case asset(Data, fileExtension: String)
    case none
}

struct SyncFields {
    private(set) var values: [String: SyncValue] = [:]

    subscript(key: String) -> SyncValue {
        get { values[key] ?? .none }
        set { values[key] = newValue }
    }

    mutating func set(_ key: String, _ value: String) { values[key] = .string(value) }
    mutating func set(_ key: String, _ value: Int) { values[key] = .int(value) }
    mutating func set(_ key: String, _ value: Double) { values[key] = .double(value) }
    mutating func set(_ key: String, _ value: Bool) { values[key] = .int(value ? 1 : 0) }
    mutating func set(_ key: String, _ value: Date?) { values[key] = value.map(SyncValue.date) ?? .none }
    mutating func set(_ key: String, _ value: UUID?) { values[key] = value.map { .string($0.uuidString) } ?? .none }

    /// Stable hash of the content, used to notice local edits between syncs.
    var fingerprint: String {
        var hasher = SHA256()
        for key in values.keys.sorted() {
            hasher.update(data: Data(key.utf8))
            switch values[key] ?? .none {
            case .string(let value): hasher.update(data: Data("s:\(value)".utf8))
            case .int(let value): hasher.update(data: Data("i:\(value)".utf8))
            case .double(let value): hasher.update(data: Data("d:\(value.bitPattern)".utf8))
            case .date(let value):
                // CloudKit keeps millisecond precision.
                hasher.update(data: Data("t:\(Int64((value.timeIntervalSince1970 * 1000).rounded()))".utf8))
            case .data(let value), .asset(let value, _):
                hasher.update(data: Data("b:".utf8))
                hasher.update(data: value)
            case .none: hasher.update(data: Data("n".utf8))
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func write(into record: CKRecord, assetName: String, tempFiles: inout [URL]) throws {
        for (key, value) in values {
            switch value {
            case .string(let value): record[key] = value as CKRecordValue
            case .int(let value): record[key] = value as CKRecordValue
            case .double(let value): record[key] = value as CKRecordValue
            case .date(let value): record[key] = value as CKRecordValue
            case .data(let value) where value.count < 900_000:
                record[key] = value as CKRecordValue
            case .data(let value):
                record[key] = try Self.asset(from: value, name: "\(assetName)-\(key).bin", tempFiles: &tempFiles)
            case .asset(let value, let ext):
                record[key] = try Self.asset(from: value, name: "\(assetName)-\(key).\(ext)", tempFiles: &tempFiles)
            case .none: record[key] = nil
            }
        }
    }

    private static func asset(from data: Data, name: String, tempFiles: inout [URL]) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        tempFiles.append(url)
        return CKAsset(fileURL: url)
    }
}

// MARK: - Field decoding

struct SyncRecordReader {
    let record: CKRecord

    func string(_ key: String) -> String? { record[key] as? String }
    func int(_ key: String) -> Int? { record[key] as? Int }
    func double(_ key: String) -> Double? { record[key] as? Double }
    func date(_ key: String) -> Date? { record[key] as? Date }
    func bool(_ key: String) -> Bool? { int(key).map { $0 != 0 } }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init) }
    func has(_ key: String) -> Bool { record[key] != nil }

    /// Inline bytes or the contents of an asset.
    func data(_ key: String) -> Data? {
        if let data = record[key] as? Data { return data }
        if let asset = record[key] as? CKAsset, let url = asset.fileURL {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}

/// Resolves relationship IDs while applying remote records.
final class SyncLookup {
    private let modelContext: ModelContext
    private var cache: [ObjectIdentifier: [UUID: any FamilySyncable]] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func find<T: FamilySyncable>(_ type: T.Type, _ id: UUID?) -> T? {
        guard let id else { return nil }
        let key = ObjectIdentifier(type)
        if cache[key] == nil {
            let all = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
            cache[key] = Dictionary(all.map { ($0.id, $0 as any FamilySyncable) }, uniquingKeysWith: { first, _ in first })
        }
        return cache[key]?[id] as? T
    }

    func member(_ id: UUID?) -> FamilyMember? { find(FamilyMember.self, id) }

    func invalidate() { cache.removeAll() }
}

// MARK: - Conformances

extension FamilyMember: FamilySyncable {
    static let syncRecordType = "SharedFamilyMember"
    static let syncPrefix = "member"
    static func makeForSync() -> FamilyMember { FamilyMember(name: "Member") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("colorHex", colorHex)
        fields.set("inviteEmail", inviteEmail)
        fields.set("invitePhone", invitePhone)
        if let data = profileImageData, !data.isEmpty {
            fields.set("hasProfileImage", 1)
            fields["profileImage"] = .asset(data, fileExtension: "jpg")
        } else {
            fields.set("hasProfileImage", 0)
            fields["profileImage"] = .none
        }
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        colorHex = record.string("colorHex") ?? colorHex
        inviteEmail = record.string("inviteEmail") ?? inviteEmail
        invitePhone = record.string("invitePhone") ?? invitePhone
        if let data = record.data("profileImage") {
            profileImageData = data
        } else if record.int("hasProfileImage") == 0 {
            profileImageData = nil
        }
    }
}

extension CalendarEvent: FamilySyncable {
    static let syncRecordType = "SharedCalendarEvent"
    static let syncPrefix = "event"
    static func makeForSync() -> CalendarEvent { CalendarEvent(title: "Event", startDate: Date(), endDate: Date()) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("title", title)
        fields.set("notes", notes)
        fields.set("startDate", startDate)
        fields.set("endDate", endDate)
        fields.set("isAllDay", isAllDay)
        fields.set("location", location)
        fields.set("notificationsEnabled", notificationsEnabled)
        fields.set("linkedSourceEventID", linkedSourceEventID)
        fields.set("linkedSourceZoneName", linkedSourceZoneName)
        fields.set("linkedSourceTribeName", linkedSourceTribeName)
        // Profiles only exist in the home tribe; leave other tribes' assignments untouched.
        if tribeZoneName.isEmpty {
            fields.set("assignedMemberID", assignedMember?.id)
        }
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        title = record.string("title") ?? title
        notes = record.string("notes") ?? ""
        startDate = record.date("startDate") ?? startDate
        endDate = record.date("endDate") ?? endDate
        isAllDay = record.bool("isAllDay") ?? isAllDay
        location = record.string("location") ?? ""
        notificationsEnabled = record.bool("notificationsEnabled") ?? notificationsEnabled
        linkedSourceEventID = record.uuid("linkedSourceEventID")
        linkedSourceZoneName = record.string("linkedSourceZoneName") ?? ""
        linkedSourceTribeName = record.string("linkedSourceTribeName") ?? ""
        if tribeZoneName.isEmpty {
            assignedMember = lookup.member(record.uuid("assignedMemberID"))
        }
    }
}

extension Chore: FamilySyncable {
    static let syncRecordType = "SharedChore"
    static let syncPrefix = "chore"
    static func makeForSync() -> Chore { Chore(title: "Chore") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("title", title)
        fields.set("notes", notes)
        fields.set("dueDate", dueDate)
        fields.set("frequencyRaw", frequencyRaw)
        fields.set("isCompleted", isCompleted)
        fields.set("completedAt", completedAt)
        fields.set("remindersEnabled", remindersEnabled)
        fields["componentsData"] = .data(componentsData)
        fields.set("assignedMemberID", assignedMember?.id)
        fields.set("boardX", boardX)
        fields.set("boardY", boardY)
        fields.set("markerColorHex", markerColorHex)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        title = record.string("title") ?? title
        notes = record.string("notes") ?? ""
        dueDate = record.date("dueDate") ?? dueDate
        frequencyRaw = record.string("frequencyRaw") ?? frequencyRaw
        isCompleted = record.bool("isCompleted") ?? isCompleted
        completedAt = record.date("completedAt")
        remindersEnabled = record.bool("remindersEnabled") ?? remindersEnabled
        if let data = record.data("componentsData") {
            componentsData = data
        }
        assignedMember = lookup.member(record.uuid("assignedMemberID"))
        boardX = record.double("boardX") ?? boardX
        boardY = record.double("boardY") ?? boardY
        markerColorHex = record.string("markerColorHex") ?? markerColorHex
    }
}

extension BoardNote: FamilySyncable {
    static let syncRecordType = "SharedBoardNote"
    static let syncPrefix = "boardNote"
    static func makeForSync() -> BoardNote { BoardNote(text: "", boardX: 0, boardY: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("text", text)
        fields.set("boardX", boardX)
        fields.set("boardY", boardY)
        fields.set("colorHex", colorHex)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        text = record.string("text") ?? text
        boardX = record.double("boardX") ?? boardX
        boardY = record.double("boardY") ?? boardY
        colorHex = record.string("colorHex") ?? colorHex
    }
}

extension Recipe: FamilySyncable {
    static let syncRecordType = "SharedRecipe"
    static let syncPrefix = "recipe"
    static func makeForSync() -> Recipe { Recipe(name: "Recipe") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("summary", summary)
        fields.set("instructions", instructions)
        fields.set("sourceURL", sourceURL)
        fields.set("imageURL", imageURL)
        fields.set("servings", servings)
        fields.set("externalID", externalID)
        fields["ingredientsData"] = .data(ingredientsData)
        if let data = imageData, !data.isEmpty {
            fields.set("hasImage", 1)
            fields["image"] = .asset(data, fileExtension: "jpg")
        } else {
            fields.set("hasImage", 0)
            fields["image"] = .none
        }
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        summary = record.string("summary") ?? ""
        instructions = record.string("instructions") ?? ""
        sourceURL = record.string("sourceURL") ?? ""
        imageURL = record.string("imageURL") ?? ""
        servings = record.int("servings") ?? servings
        externalID = record.string("externalID") ?? ""
        if let data = record.data("ingredientsData") {
            ingredientsData = data
        }
        if let data = record.data("image") {
            imageData = data
        } else if record.int("hasImage") == 0 {
            imageData = nil
        }
    }
}

extension MealPlan: FamilySyncable {
    static let syncRecordType = "SharedMealPlan"
    static let syncPrefix = "meal"
    static func makeForSync() -> MealPlan { MealPlan(date: Date(), mealType: .dinner, recipeName: "") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("date", date)
        fields.set("mealTypeRaw", mealTypeRaw)
        fields.set("recipeName", recipeName)
        fields.set("notes", notes)
        fields.set("servings", servings)
        fields.set("recipeID", recipeID)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        date = record.date("date") ?? date
        mealTypeRaw = record.string("mealTypeRaw") ?? mealTypeRaw
        recipeName = record.string("recipeName") ?? recipeName
        notes = record.string("notes") ?? ""
        servings = record.int("servings") ?? servings
        recipeID = record.uuid("recipeID")
    }
}

extension FavoriteWeeklyMealPlan: FamilySyncable {
    static let syncRecordType = "SharedFavoriteMealPlan"
    static let syncPrefix = "favoriteMealPlan"
    static func makeForSync() -> FavoriteWeeklyMealPlan { FavoriteWeeklyMealPlan(name: "") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields["slotsData"] = .data(slotsData)
        fields.set("lastUsedAt", lastUsedAt)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        if let data = record.data("slotsData") {
            slotsData = data
        }
        lastUsedAt = record.date("lastUsedAt")
    }
}

extension GroceryItem: FamilySyncable {
    static let syncRecordType = "SharedGroceryItem"
    static let syncPrefix = "grocery"
    static func makeForSync() -> GroceryItem { GroceryItem(name: "") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("quantity", quantity)
        fields.set("categoryRaw", categoryRaw)
        fields.set("isChecked", isChecked)
        fields.set("notes", notes)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        quantity = record.string("quantity") ?? quantity
        categoryRaw = record.string("categoryRaw") ?? categoryRaw
        isChecked = record.bool("isChecked") ?? isChecked
        notes = record.string("notes") ?? ""
    }
}

extension HouseholdNeed: FamilySyncable {
    static let syncRecordType = "SharedHouseholdNeed"
    static let syncPrefix = "need"
    static func makeForSync() -> HouseholdNeed { HouseholdNeed(name: "") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("quantity", quantity)
        fields.set("categoryRaw", categoryRaw)
        fields.set("priorityRaw", priorityRaw)
        fields.set("estimatedCost", estimatedCost)
        fields.set("isPurchased", isPurchased)
        fields.set("notes", notes)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        quantity = record.string("quantity") ?? quantity
        categoryRaw = record.string("categoryRaw") ?? categoryRaw
        priorityRaw = record.string("priorityRaw") ?? priorityRaw
        estimatedCost = record.double("estimatedCost") ?? estimatedCost
        isPurchased = record.bool("isPurchased") ?? isPurchased
        notes = record.string("notes") ?? ""
    }
}

extension WishListItem: FamilySyncable {
    static let syncRecordType = "SharedWishListItem"
    static let syncPrefix = "wish"
    static func makeForSync() -> WishListItem { WishListItem(name: "") }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("price", price)
        fields.set("priorityRaw", priorityRaw)
        fields.set("notes", notes)
        fields.set("link", link)
        fields.set("isPurchased", isPurchased)
        fields.set("forMemberID", forMember?.id)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        price = record.double("price") ?? price
        priorityRaw = record.string("priorityRaw") ?? priorityRaw
        notes = record.string("notes") ?? ""
        link = record.string("link") ?? ""
        isPurchased = record.bool("isPurchased") ?? isPurchased
        forMember = lookup.member(record.uuid("forMemberID"))
    }
}

extension BudgetItem: FamilySyncable {
    static let syncRecordType = "SharedBudgetItem"
    static let syncPrefix = "budgetItem"
    static func makeForSync() -> BudgetItem { BudgetItem(name: "", plannedAmount: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("plannedAmount", plannedAmount)
        fields.set("spentAmount", spentAmount)
        fields.set("categoryRaw", categoryRaw)
        fields.set("monthStart", monthStart)
        fields.set("notes", notes)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        plannedAmount = record.double("plannedAmount") ?? plannedAmount
        spentAmount = record.double("spentAmount") ?? spentAmount
        categoryRaw = record.string("categoryRaw") ?? categoryRaw
        monthStart = record.date("monthStart") ?? monthStart
        notes = record.string("notes") ?? ""
    }
}

extension BudgetExpense: FamilySyncable {
    static let syncRecordType = "SharedBudgetExpense"
    static let syncPrefix = "budgetExpense"
    static func makeForSync() -> BudgetExpense { BudgetExpense(amount: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("amount", amount)
        fields.set("note", note)
        fields.set("date", date)
        fields.set("budgetItemID", budgetItem?.id)
        fields.set("paidByID", paidBy?.id)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        amount = record.double("amount") ?? amount
        note = record.string("note") ?? ""
        date = record.date("date") ?? date
        budgetItem = lookup.find(BudgetItem.self, record.uuid("budgetItemID"))
        paidBy = lookup.member(record.uuid("paidByID"))
    }
}

extension IncomeSource: FamilySyncable {
    static let syncRecordType = "SharedIncomeSource"
    static let syncPrefix = "income"
    static func makeForSync() -> IncomeSource { IncomeSource(name: "", amount: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("amount", amount)
        fields.set("frequencyRaw", frequencyRaw)
        fields.set("nextPayDate", nextPayDate)
        fields.set("notes", notes)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        amount = record.double("amount") ?? amount
        frequencyRaw = record.string("frequencyRaw") ?? frequencyRaw
        nextPayDate = record.date("nextPayDate") ?? nextPayDate
        notes = record.string("notes") ?? ""
    }
}

extension RecurringBill: FamilySyncable {
    static let syncRecordType = "SharedRecurringBill"
    static let syncPrefix = "bill"
    static func makeForSync() -> RecurringBill { RecurringBill(name: "", amount: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("name", name)
        fields.set("amount", amount)
        fields.set("frequencyRaw", frequencyRaw)
        fields.set("nextDueDate", nextDueDate)
        fields.set("categoryRaw", categoryRaw)
        fields.set("notes", notes)
        fields.set("addToCalendar", addToCalendar)
        fields.set("remindersEnabled", remindersEnabled)
        fields.set("reminderLeadDays", reminderLeadDays)
        fields.set("linkedEventID", linkedEventID)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        name = record.string("name") ?? name
        amount = record.double("amount") ?? amount
        frequencyRaw = record.string("frequencyRaw") ?? frequencyRaw
        nextDueDate = record.date("nextDueDate") ?? nextDueDate
        categoryRaw = record.string("categoryRaw") ?? categoryRaw
        notes = record.string("notes") ?? ""
        addToCalendar = record.bool("addToCalendar") ?? addToCalendar
        remindersEnabled = record.bool("remindersEnabled") ?? remindersEnabled
        reminderLeadDays = record.int("reminderLeadDays") ?? reminderLeadDays
        linkedEventID = record.uuid("linkedEventID")
    }
}

extension VoiceMemo: FamilySyncable {
    static let syncRecordType = "SharedVoiceMemo"
    static let syncPrefix = "memo"
    static func makeForSync() -> VoiceMemo { VoiceMemo(audioData: Data(), durationSeconds: 0) }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("title", title)
        fields["audio"] = audioData.isEmpty ? .none : .asset(audioData, fileExtension: "m4a")
        fields.set("durationSeconds", durationSeconds)
        fields.set("isHeard", isHeard)
        fields.set("scheduledEventID", scheduledEventID)
        fields.set("fromMemberID", fromMember?.id)
        fields.set("toMemberID", toMember?.id)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        title = record.string("title") ?? ""
        if let data = record.data("audio") {
            audioData = data
        }
        durationSeconds = record.double("durationSeconds") ?? durationSeconds
        isHeard = record.bool("isHeard") ?? isHeard
        scheduledEventID = record.uuid("scheduledEventID")
        fromMember = lookup.member(record.uuid("fromMemberID"))
        toMember = lookup.member(record.uuid("toMemberID"))
    }
}

extension PendingEmailImport: FamilySyncable {
    static let syncRecordType = "SharedEmailImport"
    static let syncPrefix = "emailImport"
    static func makeForSync() -> PendingEmailImport {
        PendingEmailImport(title: "", startDate: Date(), endDate: Date(), isAllDay: false, category: .other)
    }

    func encodeSyncFields(into fields: inout SyncFields) {
        fields.set("title", title)
        fields.set("startDate", startDate)
        fields.set("endDate", endDate)
        fields.set("isAllDay", isAllDay)
        fields.set("location", location)
        fields.set("notes", notes)
        fields.set("categoryRaw", categoryRaw)
        fields.set("sourceSnippet", sourceSnippet)
        fields.set("statusRaw", statusRaw)
        fields.set("suggestedMemberID", suggestedMember?.id)
    }

    func applySyncFields(from record: SyncRecordReader, lookup: SyncLookup) {
        title = record.string("title") ?? title
        startDate = record.date("startDate") ?? startDate
        endDate = record.date("endDate") ?? endDate
        isAllDay = record.bool("isAllDay") ?? isAllDay
        location = record.string("location") ?? ""
        notes = record.string("notes") ?? ""
        categoryRaw = record.string("categoryRaw") ?? categoryRaw
        sourceSnippet = record.string("sourceSnippet") ?? ""
        statusRaw = record.string("statusRaw") ?? statusRaw
        suggestedMember = lookup.member(record.uuid("suggestedMemberID"))
    }
}
