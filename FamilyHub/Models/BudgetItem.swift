import Foundation
import SwiftData

enum BudgetCategoryKind: String, Codable, CaseIterable, Identifiable {
    case housing, food, utilities, transport, kids, health, entertainment, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .housing: "Housing"
        case .food: "Food"
        case .utilities: "Utilities"
        case .transport: "Transport"
        case .kids: "Kids"
        case .health: "Health"
        case .entertainment: "Fun"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .housing: "house.fill"
        case .food: "cart.fill"
        case .utilities: "bolt.fill"
        case .transport: "car.fill"
        case .kids: "figure.2.and.child.holdinghands"
        case .health: "cross.case.fill"
        case .entertainment: "gamecontroller.fill"
        case .other: "dollarsign.circle.fill"
        }
    }
}

@Model
final class BudgetItem {
    var id: UUID = UUID()
    var name: String = ""
    var plannedAmount: Double = 0
    var spentAmount: Double = 0
    var categoryRaw: String = BudgetCategoryKind.other.rawValue
    var monthStart: Date = Date()
    var notes: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BudgetExpense.budgetItem)
    var expenses: [BudgetExpense]?

    init(
        name: String,
        plannedAmount: Double,
        spentAmount: Double = 0,
        category: BudgetCategoryKind = .other,
        monthStart: Date = Date().startOfMonth,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.plannedAmount = plannedAmount
        self.spentAmount = spentAmount
        self.categoryRaw = category.rawValue
        self.monthStart = Calendar.current.startOfDay(for: monthStart.startOfMonth)
        self.notes = notes
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    var category: BudgetCategoryKind {
        get { BudgetCategoryKind(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var sortedExpenses: [BudgetExpense] {
        (expenses ?? []).sorted { $0.date > $1.date }
    }

    var remaining: Double {
        plannedAmount - spentAmount
    }

    var progress: Double {
        guard plannedAmount > 0 else { return spentAmount > 0 ? 1 : 0 }
        return min(spentAmount / plannedAmount, 1.5)
    }

    var isOverBudget: Bool {
        spentAmount > plannedAmount
    }

    func recalculateSpentAmount() {
        spentAmount = (expenses ?? []).reduce(0) { $0 + $1.amount }
    }
}
