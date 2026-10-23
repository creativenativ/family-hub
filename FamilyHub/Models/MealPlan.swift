import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}

@Model
final class MealPlan {
    var id: UUID = UUID()
    var date: Date = Date()
    var mealTypeRaw: String = MealType.dinner.rawValue
    var recipeName: String = ""
    var notes: String = ""
    var servings: Int = 4
    var recipeID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(
        date: Date,
        mealType: MealType,
        recipeName: String,
        notes: String = "",
        servings: Int = 4,
        recipeID: UUID? = nil
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.mealTypeRaw = mealType.rawValue
        self.recipeName = recipeName
        self.notes = notes
        self.servings = servings
        self.recipeID = recipeID
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }
}
