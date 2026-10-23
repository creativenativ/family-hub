import Foundation
import SwiftData

enum MoneyFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly, biweekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }

    var dayInterval: Int {
        switch self {
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30
        }
    }
}

@Model
final class IncomeSource {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var frequencyRaw: String = MoneyFrequency.biweekly.rawValue
    var nextPayDate: Date = Date()
    var notes: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(
        name: String,
        amount: Double,
        frequency: MoneyFrequency = .biweekly,
        nextPayDate: Date = Date(),
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.nextPayDate = Calendar.current.startOfDay(for: nextPayDate)
        self.notes = notes
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    var frequency: MoneyFrequency {
        get { MoneyFrequency(rawValue: frequencyRaw) ?? .biweekly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Ensures nextPayDate is today or in the future.
    func advancePayDateIfNeeded(reference: Date = Date()) {
        let calendar = Calendar.current
        var next = calendar.startOfDay(for: nextPayDate)
        let today = calendar.startOfDay(for: reference)
        while next < today {
            next = Self.dateByAdding(frequency: frequency, to: next, calendar: calendar)
        }
        nextPayDate = next
    }

    /// Pay period that contains `reference`, ending on the upcoming payday.
    /// Read-only — does not mutate `nextPayDate` (advance separately on the main actor).
    func payPeriod(containing reference: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        var end = calendar.startOfDay(for: nextPayDate)
        let today = calendar.startOfDay(for: reference)
        while end < today {
            end = Self.dateByAdding(frequency: frequency, to: end, calendar: calendar)
        }
        let start = Self.dateByAdding(frequency: frequency, to: end, calendar: calendar, multiplier: -1)
        return (start, end)
    }

    static func dateByAdding(
        frequency: MoneyFrequency,
        to date: Date,
        calendar: Calendar = .current,
        multiplier: Int = 1
    ) -> Date {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * multiplier, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14 * multiplier, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: multiplier, to: date) ?? date
        }
    }
}
