import Foundation
import SwiftData

/// One meal slot inside a saved weekly template (day 0 = start of week).
struct FavoriteMealSlot: Codable, Hashable, Identifiable {
    var id: UUID
    var dayOffset: Int
    var mealTypeRaw: String
    var recipeName: String
    var notes: String
    var servings: Int
    var recipeID: UUID?

    init(
        id: UUID = UUID(),
        dayOffset: Int,
        mealType: MealType,
        recipeName: String,
        notes: String = "",
        servings: Int = 4,
        recipeID: UUID? = nil
    ) {
        self.id = id
        self.dayOffset = dayOffset
        self.mealTypeRaw = mealType.rawValue
        self.recipeName = recipeName
        self.notes = notes
        self.servings = servings
        self.recipeID = recipeID
    }

    var mealType: MealType {
        MealType(rawValue: mealTypeRaw) ?? .dinner
    }
}

/// A reusable week of meal selections the tribe can apply to any week.
@Model
final class FavoriteWeeklyMealPlan {
    var id: UUID = UUID()
    var name: String = ""
    var slotsData: Data = Data()
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init(name: String, slots: [FavoriteMealSlot] = []) {
        self.id = UUID()
        self.name = name
        self.slotsData = (try? JSONEncoder().encode(slots)) ?? Data()
        self.createdAt = Date()
        self.lastUsedAt = nil
    }

    var slots: [FavoriteMealSlot] {
        get {
            (try? JSONDecoder().decode([FavoriteMealSlot].self, from: slotsData)) ?? []
        }
        set {
            slotsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var mealCount: Int { slots.count }

    var previewSummary: String {
        let names = slots.map(\.recipeName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Empty plan" }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        }
        return names.prefix(3).joined(separator: ", ") + " +\(names.count - 3) more"
    }

    static func slots(from meals: [MealPlan], weekStart: Date) -> [FavoriteMealSlot] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        return meals.compactMap { meal in
            let day = calendar.startOfDay(for: meal.date)
            let offset = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            guard (0..<7).contains(offset) else { return nil }
            return FavoriteMealSlot(
                dayOffset: offset,
                mealType: meal.mealType,
                recipeName: meal.recipeName,
                notes: meal.notes,
                servings: meal.servings,
                recipeID: meal.recipeID
            )
        }
        .sorted {
            if $0.dayOffset != $1.dayOffset { return $0.dayOffset < $1.dayOffset }
            return $0.mealTypeRaw < $1.mealTypeRaw
        }
    }

    /// Applies this template onto `weekStart`, replacing any meals already in those slots.
    @discardableResult
    func apply(toWeekStarting weekStart: Date, replacing existingMeals: [MealPlan], in context: ModelContext) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        var applied = 0

        for slot in slots {
            guard let day = calendar.date(byAdding: .day, value: slot.dayOffset, to: start) else { continue }
            let dayStart = calendar.startOfDay(for: day)

            for existing in existingMeals where existing.date.isSameDay(as: dayStart) && existing.mealType == slot.mealType {
                context.delete(existing)
            }

            let meal = MealPlan(
                date: dayStart,
                mealType: slot.mealType,
                recipeName: slot.recipeName,
                notes: slot.notes,
                servings: slot.servings,
                recipeID: slot.recipeID
            )
            context.insert(meal)
            applied += 1
        }

        lastUsedAt = Date()
        return applied
    }
}
