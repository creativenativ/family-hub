import Foundation
import SwiftData

enum GroceryCategory: String, Codable, CaseIterable, Identifiable {
    case produce, dairy, meat, bakery, frozen, pantry, beverages, household, other

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .produce: "leaf.fill"
        case .dairy: "drop.fill"
        case .meat: "fork.knife"
        case .bakery: "birthday.cake.fill"
        case .frozen: "snowflake"
        case .pantry: "cabinet.fill"
        case .beverages: "cup.and.saucer.fill"
        case .household: "house.fill"
        case .other: "cart.fill"
        }
    }
}

@Model
final class GroceryItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: String = "1"
    var categoryRaw: String = GroceryCategory.other.rawValue
    var isChecked: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(
        name: String,
        quantity: String = "1",
        category: GroceryCategory = .other,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.isChecked = false
        self.notes = notes
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    var category: GroceryCategory {
        get { GroceryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
