import Foundation
import SwiftData

enum BillReminderLead: Int, Codable, CaseIterable, Identifiable {
    case dayOf = 0
    case oneDay = 1
    case threeDays = 3
    case oneWeek = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .dayOf: "Day of payment"
        case .oneDay: "1 day before"
        case .threeDays: "3 days before"
        case .oneWeek: "1 week before"
        }
    }
}

@Model
final class RecurringBill {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var frequencyRaw: String = MoneyFrequency.monthly.rawValue
    var nextDueDate: Date = Date()
    var categoryRaw: String = BudgetCategoryKind.other.rawValue
    var notes: String = ""
    var addToCalendar: Bool = true
    var remindersEnabled: Bool = true
    var reminderLeadDays: Int = BillReminderLead.threeDays.rawValue
    var linkedEventID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(
        name: String,
        amount: Double,
        frequency: MoneyFrequency = .monthly,
        nextDueDate: Date = Date(),
        category: BudgetCategoryKind = .other,
        notes: String = "",
        addToCalendar: Bool = true,
        remindersEnabled: Bool = true,
        reminderLead: BillReminderLead = .threeDays
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.nextDueDate = Calendar.current.startOfDay(for: nextDueDate)
        self.categoryRaw = category.rawValue
        self.notes = notes
        self.addToCalendar = addToCalendar
        self.remindersEnabled = remindersEnabled
        self.reminderLeadDays = reminderLead.rawValue
        self.linkedEventID = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    var frequency: MoneyFrequency {
        get { MoneyFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var category: BudgetCategoryKind {
        get { BudgetCategoryKind(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var reminderLead: BillReminderLead {
        get { BillReminderLead(rawValue: reminderLeadDays) ?? .threeDays }
        set { reminderLeadDays = newValue.rawValue }
    }

    func advanceDueDateIfNeeded(reference: Date = Date()) {
        let calendar = Calendar.current
        var next = calendar.startOfDay(for: nextDueDate)
        let today = calendar.startOfDay(for: reference)
        while next < today {
            next = IncomeSource.dateByAdding(frequency: frequency, to: next, calendar: calendar)
        }
        nextDueDate = next
    }

    func markPaidAndAdvance() {
        let calendar = Calendar.current
        let due = calendar.startOfDay(for: nextDueDate)
        nextDueDate = IncomeSource.dateByAdding(frequency: frequency, to: due, calendar: calendar)
    }
}
