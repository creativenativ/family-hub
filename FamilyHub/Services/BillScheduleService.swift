import Foundation
import SwiftData
import UserNotifications

enum BillScheduleService {
    static let categoryID = "BILL_REMINDER"

    // MARK: - Notifications

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func scheduleReminder(for bill: RecurringBill) async {
        await cancelReminder(for: bill.id)
        let prefsEnabled = await MainActor.run { NotificationPreferences.shared.billsEnabled }
        guard prefsEnabled, bill.remindersEnabled else { return }

        let granted = await permissionGranted()
        guard granted else { return }

        bill.advanceDueDateIfNeeded()
        guard let fireDate = reminderFireDate(for: bill) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming bill"
        let amount = bill.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        content.body = "\(bill.name) · \(amount) due \(bill.nextDueDate.formatted())"
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["billID": bill.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: bill.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelReminder(for billID: UUID) async {
        let id = notificationID(for: billID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    static func cancelAllBillReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("bill-reminder-") }
            .map(\.identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func rescheduleAll(for bills: [RecurringBill]) async {
        for bill in bills {
            await scheduleReminder(for: bill)
        }
    }

    private static func notificationID(for billID: UUID) -> String {
        "bill-reminder-\(billID.uuidString)"
    }

    private static func permissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Reminds at 9:00 AM on (due date − lead days). If that already passed, nudge in 5 minutes when still before/on due date.
    private static func reminderFireDate(for bill: RecurringBill) -> Date? {
        let calendar = Calendar.current
        let dueDay = calendar.startOfDay(for: bill.nextDueDate)
        let notifyDay = calendar.date(byAdding: .day, value: -bill.reminderLeadDays, to: dueDay) ?? dueDay
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: notifyDay) ?? notifyDay
        let now = Date()

        if morning > now {
            return morning
        }

        // Still before end of due day — remind soon
        if now < calendar.date(byAdding: .day, value: 1, to: dueDay) ?? dueDay {
            return calendar.date(byAdding: .minute, value: 5, to: now)
        }
        return nil
    }

    // MARK: - Calendar

    @MainActor
    static func syncCalendarEvent(for bill: RecurringBill, in context: ModelContext) {
        bill.advanceDueDateIfNeeded()

        if !bill.addToCalendar {
            if let eventID = bill.linkedEventID,
               let event = fetchEvent(id: eventID, in: context) {
                FamilySyncService.shared.noteLocalDeletion(prefix: "event", id: event.id)
                context.delete(event)
            }
            bill.linkedEventID = nil
            return
        }

        let start = Calendar.current.startOfDay(for: bill.nextDueDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let amount = bill.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let title = "Bill: \(bill.name)"
        let notes = [
            "Amount: \(amount)",
            "Repeats: \(bill.frequency.label)",
            bill.notes,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        if let eventID = bill.linkedEventID,
           let event = fetchEvent(id: eventID, in: context) {
            event.title = title
            event.startDate = start
            event.endDate = end
            event.isAllDay = true
            event.notes = notes
            event.location = ""
            event.notificationsEnabled = false
            event.touchForSync()
        } else {
            let event = CalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                isAllDay: true,
                notes: notes,
                notificationsEnabled: false
            )
            context.insert(event)
            bill.linkedEventID = event.id
        }
    }

    @MainActor
    static func removeCalendarEvent(for bill: RecurringBill, in context: ModelContext) {
        if let eventID = bill.linkedEventID,
           let event = fetchEvent(id: eventID, in: context) {
            FamilySyncService.shared.noteLocalDeletion(prefix: "event", id: event.id)
            context.delete(event)
        }
        bill.linkedEventID = nil
    }

    @MainActor
    private static func fetchEvent(id: UUID, in context: ModelContext) -> CalendarEvent? {
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}
