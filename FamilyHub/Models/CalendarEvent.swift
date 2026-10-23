import Foundation
import SwiftData

@Model
final class CalendarEvent {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var isAllDay: Bool = false
    var location: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false
    /// When false, skip calendar push notifications (e.g. bill-linked events use bill reminders).
    var notificationsEnabled: Bool = true

    var assignedMember: FamilyMember?

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        notes: String = "",
        location: String = "",
        assignedMember: FamilyMember? = nil,
        notificationsEnabled: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
        self.notificationsEnabled = notificationsEnabled
        self.assignedMember = assignedMember
    }

    func touchForSync() {
        modifiedAt = Date()
    }
}
