import Foundation
import SwiftData
import SwiftUI
import UIKit

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = MemberColor.blue.hex
    var profileImageData: Data?
    var inviteEmail: String = ""
    var invitePhone: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \CalendarEvent.assignedMember)
    var events: [CalendarEvent]?

    @Relationship(deleteRule: .nullify, inverse: \Chore.assignedMember)
    var chores: [Chore]?

    @Relationship(deleteRule: .nullify, inverse: \VoiceMemo.fromMember)
    var sentMemos: [VoiceMemo]?

    @Relationship(deleteRule: .nullify, inverse: \VoiceMemo.toMember)
    var receivedMemos: [VoiceMemo]?

    @Relationship(deleteRule: .nullify, inverse: \PendingEmailImport.suggestedMember)
    var pendingImports: [PendingEmailImport]?

    @Relationship(deleteRule: .nullify, inverse: \WishListItem.forMember)
    var wishListItems: [WishListItem]?

    @Relationship(deleteRule: .nullify, inverse: \BudgetExpense.paidBy)
    var budgetExpenses: [BudgetExpense]?

    init(name: String, colorHex: String = MemberColor.blue.hex, profileImageData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.profileImageData = profileImageData
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    func touchForSync() {
        modifiedAt = Date()
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var profileImage: UIImage? {
        guard let profileImageData else { return nil }
        return UIImage(data: profileImageData)
    }

    var initial: String {
        name.prefix(1).uppercased()
    }
}

enum MemberColor: String, CaseIterable, Identifiable {
    case blue, green, orange, purple, pink, red, teal, yellow

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .blue: "#007AFF"
        case .green: "#34C759"
        case .orange: "#FF9500"
        case .purple: "#AF52DE"
        case .pink: "#FF2D55"
        case .red: "#FF3B30"
        case .teal: "#5AC8FA"
        case .yellow: "#FFCC00"
        }
    }

    var color: Color {
        Color(hex: hex) ?? .blue
    }

    var label: String {
        rawValue.capitalized
    }

    static func closest(to hex: String) -> MemberColor {
        allCases.first { $0.hex == hex } ?? .blue
    }
}
