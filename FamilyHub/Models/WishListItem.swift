import Foundation
import SwiftData

enum WishPriority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

@Model
final class WishListItem {
    var id: UUID = UUID()
    var name: String = ""
    var price: Double = 0
    var priorityRaw: String = WishPriority.medium.rawValue
    var notes: String = ""
    var link: String = ""
    var isPurchased: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    var forMember: FamilyMember?

    init(
        name: String,
        price: Double = 0,
        priority: WishPriority = .medium,
        notes: String = "",
        link: String = "",
        forMember: FamilyMember? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.priorityRaw = priority.rawValue
        self.notes = notes
        self.link = link
        self.isPurchased = false
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
        self.forMember = forMember
    }

    var priority: WishPriority {
        get { WishPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}
