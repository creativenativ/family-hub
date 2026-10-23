import Foundation
import SwiftData
import UserNotifications

enum EventReminderService {
    static let categoryID = "EVENT_REMINDER"

    static func scheduleReminder(for event: CalendarEvent) async {
        await cancelReminder(for: event.id)

        guard await MainActor.run(body: { NotificationPreferences.shared.calendarEventsEnabled }),
              event.notificationsEnabled else { return }

        let granted = await permissionGranted()
        guard granted else { return }
        guard let fireDate = reminderFireDate(for: event), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming event"
        if event.isAllDay {
            content.body = "\(event.title) · today"
        } else {
            content.body = "\(event.title) · \(event.startDate.formattedTime())"
        }
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["eventID": event.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: event.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelReminder(for eventID: UUID) async {
        let id = notificationID(for: eventID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    static func cancelAllEventReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("event-reminder-") }
            .map(\.identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func rescheduleAll(for events: [CalendarEvent]) async {
        for event in events {
            await scheduleReminder(for: event)
        }
    }

    private static func notificationID(for eventID: UUID) -> String {
        "event-reminder-\(eventID.uuidString)"
    }

    private static func permissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    private static func reminderFireDate(for event: CalendarEvent) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        if event.isAllDay {
            let day = calendar.startOfDay(for: event.startDate)
            let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
            if morning > now { return morning }
            if calendar.isDateInToday(event.startDate) {
                return calendar.date(byAdding: .minute, value: 5, to: now)
            }
            return nil
        }

        // Timed: 1 hour before start
        if let hourBefore = calendar.date(byAdding: .hour, value: -1, to: event.startDate),
           hourBefore > now {
            return hourBefore
        }
        // Starting soon — never schedule after the event begins
        if event.startDate > now {
            let soon = calendar.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
            return min(soon, event.startDate)
        }
        return nil
    }
}
