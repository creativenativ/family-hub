import Foundation
import SwiftData

@Model
final class BudgetExpense {
    var id: UUID = UUID()
    var amount: Double = 0
    var note: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()

    var budgetItem: BudgetItem?
    var paidBy: FamilyMember?

    init(
        amount: Double,
        note: String = "",
        date: Date = Date(),
        budgetItem: BudgetItem? = nil,
        paidBy: FamilyMember? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.note = note
        self.date = date
        self.createdAt = Date()
        self.budgetItem = budgetItem
        self.paidBy = paidBy
    }
}
