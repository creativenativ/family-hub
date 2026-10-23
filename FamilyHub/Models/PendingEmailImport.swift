import Foundation
import SwiftData
import SwiftUI

@Model
final class PendingEmailImport {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var isAllDay: Bool = false
    var location: String = ""
    var notes: String = ""
    var categoryRaw: String = EmailEventCategory.other.rawValue
    var sourceSnippet: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false
    var statusRaw: String = PendingImportStatus.pending.rawValue

    var suggestedMember: FamilyMember?

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String = "",
        notes: String = "",
        category: EmailEventCategory,
        sourceSnippet: String = "",
        suggestedMember: FamilyMember? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.categoryRaw = category.rawValue
        self.sourceSnippet = sourceSnippet
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
        self.statusRaw = PendingImportStatus.pending.rawValue
        self.suggestedMember = suggestedMember
    }

    var category: EmailEventCategory {
        get { EmailEventCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: PendingImportStatus {
        get { PendingImportStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

enum PendingImportStatus: String, Codable {
    case pending
    case approved
    case declined
}
