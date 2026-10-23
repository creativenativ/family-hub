import Foundation
import Observation

/// Global toggles for which notification categories Tribe Time may schedule on this device.
@MainActor
@Observable
final class NotificationPreferences {
    static let shared = NotificationPreferences()

    private enum Key {
        static let chores = "NotificationPreferences.chores"
        static let bills = "NotificationPreferences.bills"
        static let calendarEvents = "NotificationPreferences.calendarEvents"
    }

    var choresEnabled: Bool {
        didSet { UserDefaults.standard.set(choresEnabled, forKey: Key.chores) }
    }

    var billsEnabled: Bool {
        didSet { UserDefaults.standard.set(billsEnabled, forKey: Key.bills) }
    }

    var calendarEventsEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarEventsEnabled, forKey: Key.calendarEvents) }
    }

    private init() {
        let defaults = UserDefaults.standard
        // Default on for existing categories; calendar off until user opts in (new).
        choresEnabled = defaults.object(forKey: Key.chores) as? Bool ?? true
        billsEnabled = defaults.object(forKey: Key.bills) as? Bool ?? true
        calendarEventsEnabled = defaults.object(forKey: Key.calendarEvents) as? Bool ?? false
    }
}

enum NotificationCategoryKind: String, CaseIterable, Identifiable {
    case chores
    case bills
    case calendarEvents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chores: "Chores"
        case .bills: "Bills & payments"
        case .calendarEvents: "Calendar events"
        }
    }

    var subtitle: String {
        switch self {
        case .chores: "Due-date reminders for assigned chores (8 AM)"
        case .bills: "Upcoming payment reminders you set on each bill"
        case .calendarEvents: "Reminders the morning of all-day events, or 1 hour before timed ones"
        }
    }

    var systemImage: String {
        switch self {
        case .chores: "checklist"
        case .bills: "doc.text"
        case .calendarEvents: "calendar"
        }
    }
}
