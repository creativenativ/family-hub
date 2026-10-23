import Foundation
import UserNotifications

enum ChoreReminderService {
    static let categoryID = "CHORE_REMINDER"

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func scheduleReminder(for chore: Chore) async {
        await cancelReminder(for: chore.id)

        let prefsEnabled = await MainActor.run { NotificationPreferences.shared.choresEnabled }
        guard prefsEnabled,
              !chore.isCompleted,
              chore.assignedMember != nil,
              chore.remindersEnabled else { return }

        let granted = await currentPermissionGranted()
        guard granted else { return }

        guard let fireDate = reminderFireDate(for: chore) else { return }

        let content = UNMutableNotificationContent()
        let memberName = chore.assignedMember?.name ?? "Tribe"
        content.title = "Chore for \(memberName)"
        content.body = chore.title
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "choreID": chore.id.uuidString,
            "memberID": chore.assignedMember?.id.uuidString ?? "",
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: chore.id),
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelReminder(for choreID: UUID) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: choreID)])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notificationID(for: choreID)])
    }

    static func cancelAllChoreReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("chore-reminder-") }
            .map(\.identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func rescheduleAll(for chores: [Chore]) async {
        for chore in chores {
            await scheduleReminder(for: chore)
        }
    }

    private static func notificationID(for choreID: UUID) -> String {
        "chore-reminder-\(choreID.uuidString)"
    }

    private static func currentPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Reminds at 8:00 AM on the due date. If due today and morning already passed, reminds soon once.
    /// Past-due chores (before today) are not re-armed on every screen appear.
    private static func reminderFireDate(for chore: Chore) -> Date? {
        let calendar = Calendar.current
        let dueDay = calendar.startOfDay(for: chore.dueDate)
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dueDay) ?? dueDay
        let now = Date()

        if morning > now {
            return morning
        }

        if calendar.isDateInToday(chore.dueDate) {
            return calendar.date(byAdding: .minute, value: 5, to: now)
        }

        return nil
    }
}
