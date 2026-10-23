import Foundation
import SwiftData

enum NeedPriority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

enum HouseholdNeedCategory: String, Codable, CaseIterable, Identifiable {
    case cleaning, paper, toiletries, laundry, kitchen, maintenance, pets, other

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .cleaning: "sparkles"
        case .paper: "doc.fill"
        case .toiletries: "drop.fill"
        case .laundry: "tshirt.fill"
        case .kitchen: "fork.knife"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .pets: "pawprint.fill"
        case .other: "house.fill"
        }
    }
}

@Model
final class HouseholdNeed {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: String = "1"
    var categoryRaw: String = HouseholdNeedCategory.other.rawValue
    var priorityRaw: String = NeedPriority.medium.rawValue
    var estimatedCost: Double = 0
    var isPurchased: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()

    init(
        name: String,
        quantity: String = "1",
        category: HouseholdNeedCategory = .other,
        priority: NeedPriority = .medium,
        estimatedCost: Double = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.estimatedCost = estimatedCost
        self.isPurchased = false
        self.notes = notes
        self.createdAt = Date()
    }

    var category: HouseholdNeedCategory {
        get { HouseholdNeedCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var priority: NeedPriority {
        get { NeedPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}
