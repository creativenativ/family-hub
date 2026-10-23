import Foundation
import SwiftData

enum RecipeSearchService {
    private static let baseURL = "https://www.themealdb.com/api/json/v1/1"

    private static let knownCategories: Set<String> = [
        "Beef", "Breakfast", "Chicken", "Dessert", "Goat", "Lamb",
        "Miscellaneous", "Pasta", "Pork", "Seafood", "Side", "Starter",
        "Vegan", "Vegetarian",
    ]

    private static let knownAreas: Set<String> = [
        "American", "British", "Canadian", "Chinese", "Croatian", "Dutch",
        "Egyptian", "Filipino", "French", "Greek", "Indian", "Irish",
        "Italian", "Jamaican", "Japanese", "Kenyan", "Malaysian", "Mexican",
        "Moroccan", "Polish", "Portuguese", "Russian", "Spanish", "Thai",
        "Tunisian", "Turkish", "Ukrainian", "Uruguayan", "Vietnamese",
    ]

    enum SearchError: LocalizedError {
        case invalidQuery
        case badResponse
        case decodingFailed
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidQuery: "Enter a recipe name to search."
            case .badResponse: "Couldn't reach the recipe service. Check your connection."
            case .decodingFailed: "Couldn't read the recipe results."
            case .notFound: "No recipes found for that search."
            }
        }
    }

    /// Searches by name, ingredient, and matching category/cuisine, then merges results.
    static func search(query: String) async throws -> [RemoteRecipeSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw SearchError.invalidQuery }

        async let nameResults = searchByName(trimmed)
        async let ingredientResults = filterMeals(parameter: "i", value: ingredientQuery(from: trimmed))
        async let categoryResults: [RemoteRecipeSummary] = {
            if let category = matchedCategory(for: trimmed) {
                return (try? await filterMeals(parameter: "c", value: category)) ?? []
            }
            return []
        }()
        async let areaResults: [RemoteRecipeSummary] = {
            if let area = matchedArea(for: trimmed) {
                return (try? await filterMeals(parameter: "a", value: area)) ?? []
            }
            return []
        }()

        // Extra ingredient hits for multi-word queries (e.g. "chicken pasta")
        let words = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { $0.count >= 3 }
        var wordIngredientBatches: [[RemoteRecipeSummary]] = []
        if words.count > 1 {
            await withTaskGroup(of: [RemoteRecipeSummary].self) { group in
                for word in words.prefix(3) {
                    group.addTask {
                        (try? await filterMeals(parameter: "i", value: ingredientQuery(from: word))) ?? []
                    }
                }
                for await batch in group {
                    wordIngredientBatches.append(batch)
                }
            }
        }

        let merged = mergeResults(
            preferFirst: try await nameResults,
            then: [
                try await ingredientResults,
                await categoryResults,
                await areaResults,
            ] + wordIngredientBatches
        )

        guard !merged.isEmpty else { throw SearchError.notFound }

        return await enrichMissingDescriptions(merged, limit: 20)
    }

    static func detail(id: String) async throws -> RemoteRecipeDetail {
        guard var components = URLComponents(string: "\(baseURL)/lookup.php") else {
            throw SearchError.badResponse
        }
        components.queryItems = [URLQueryItem(name: "i", value: id)]
        guard let url = components.url else { throw SearchError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SearchError.badResponse
        }

        do {
            let decoded = try JSONDecoder().decode(MealDBSearchResponse.self, from: data)
            guard let meal = decoded.meals?.first else { throw SearchError.notFound }

            return RemoteRecipeDetail(
                id: meal.idMeal,
                name: meal.strMeal,
                category: meal.strCategory,
                area: meal.strArea,
                instructions: meal.strInstructions ?? "",
                thumbnailURL: meal.strMealThumb,
                sourceURL: meal.strSource,
                youtubeURL: meal.strYoutube,
                ingredients: meal.parsedIngredients()
            )
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.decodingFailed
        }
    }

    // MARK: - Endpoints

    private static func searchByName(_ query: String) async throws -> [RemoteRecipeSummary] {
        guard var components = URLComponents(string: "\(baseURL)/search.php") else {
            throw SearchError.badResponse
        }
        components.queryItems = [URLQueryItem(name: "s", value: query)]
        guard let url = components.url else { throw SearchError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SearchError.badResponse
        }

        let decoded = try JSONDecoder().decode(MealDBSearchResponse.self, from: data)
        return (decoded.meals ?? []).map { meal in
            RemoteRecipeSummary(
                id: meal.idMeal,
                name: meal.strMeal,
                thumbnailURL: meal.strMealThumb,
                category: meal.strCategory,
                area: meal.strArea,
                description: previewDescription(from: meal.strInstructions),
                matchSource: .name
            )
        }
    }

    private static func filterMeals(parameter: String, value: String) async throws -> [RemoteRecipeSummary] {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        guard var components = URLComponents(string: "\(baseURL)/filter.php") else {
            throw SearchError.badResponse
        }
        components.queryItems = [URLQueryItem(name: parameter, value: cleaned)]
        guard let url = components.url else { throw SearchError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SearchError.badResponse
        }

        let decoded = try JSONDecoder().decode(MealDBFilterResponse.self, from: data)
        let source: RemoteRecipeSummary.MatchSource = switch parameter {
        case "i": .ingredient
        case "c": .category
        case "a": .cuisine
        default: .ingredient
        }

        return (decoded.meals ?? []).map {
            RemoteRecipeSummary(
                id: $0.idMeal,
                name: $0.strMeal,
                thumbnailURL: $0.strMealThumb,
                category: parameter == "c" ? cleaned : nil,
                area: parameter == "a" ? cleaned : nil,
                description: nil,
                matchSource: source
            )
        }
    }

    // MARK: - Merge / enrich

    private static func mergeResults(
        preferFirst primary: [RemoteRecipeSummary],
        then others: [[RemoteRecipeSummary]]
    ) -> [RemoteRecipeSummary] {
        var ordered: [RemoteRecipeSummary] = []
        var seen = Set<String>()

        func append(_ items: [RemoteRecipeSummary]) {
            for item in items where !seen.contains(item.id) {
                seen.insert(item.id)
                ordered.append(item)
            }
        }

        append(primary)
        for batch in others {
            append(batch)
        }
        return ordered
    }

    private static func enrichMissingDescriptions(
        _ items: [RemoteRecipeSummary],
        limit: Int
    ) async -> [RemoteRecipeSummary] {
        var result = items
        let indices = result.indices.filter {
            result[$0].description == nil || result[$0].description?.isEmpty == true
        }
        .prefix(limit)

        guard !indices.isEmpty else { return result }

        var updates: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for index in indices {
                let id = result[index].id
                group.addTask {
                    guard let detail = try? await detail(id: id) else { return (index, nil) }
                    return (index, previewDescription(from: detail.instructions))
                }
            }
            for await (index, preview) in group {
                if let preview, !preview.isEmpty {
                    updates[index] = preview
                }
            }
        }

        for (index, preview) in updates {
            let existing = result[index]
            result[index] = RemoteRecipeSummary(
                id: existing.id,
                name: existing.name,
                thumbnailURL: existing.thumbnailURL,
                category: existing.category,
                area: existing.area,
                description: preview,
                matchSource: existing.matchSource
            )
        }
        return result
    }

    // MARK: - Helpers

    private static func previewDescription(from instructions: String?) -> String? {
        guard var text = instructions?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }

        text = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let limit = 140
        guard text.count > limit else { return text }

        let end = text.index(text.startIndex, offsetBy: limit)
        var slice = String(text[..<end])
        if let lastSpace = slice.lastIndex(of: " "), lastSpace > slice.startIndex {
            slice = String(slice[..<lastSpace])
        }
        return slice.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func ingredientQuery(from raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func matchedCategory(for query: String) -> String? {
        knownCategories.first { $0.caseInsensitiveCompare(query) == .orderedSame }
    }

    private static func matchedArea(for query: String) -> String? {
        knownAreas.first { $0.caseInsensitiveCompare(query) == .orderedSame }
    }
}

struct RemoteRecipeSummary: Identifiable, Hashable {
    enum MatchSource: String, Hashable {
        case name
        case ingredient
        case category
        case cuisine
    }

    let id: String
    let name: String
    let thumbnailURL: String?
    let category: String?
    let area: String?
    let description: String?
    let matchSource: MatchSource
}

struct RemoteRecipeDetail {
    let id: String
    let name: String
    let category: String?
    let area: String?
    let instructions: String
    let thumbnailURL: String?
    let sourceURL: String?
    let youtubeURL: String?
    let ingredients: [RecipeIngredient]
}

enum GroceryIngredientMapper {
    struct AddResult: Equatable {
        var added: Int = 0
        var updated: Int = 0
        var mealsUsed: Int = 0
        var mealsSkipped: Int = 0

        var totalTouched: Int { added + updated }

        var isEmpty: Bool { mealsUsed == 0 && mealsSkipped == 0 }
    }

    static func category(for ingredientName: String) -> GroceryCategory {
        let name = ingredientName.lowercased()

        let produce = ["lettuce", "tomato", "onion", "garlic", "pepper", "carrot", "potato", "lemon", "lime", "apple", "banana", "spinach", "broccoli", "celery", "cucumber", "avocado", "herb", "parsley", "cilantro", "basil", "ginger", "mushroom", "zucchini", "corn", "berry"]
        let dairy = ["milk", "cheese", "butter", "cream", "yogurt", "egg"]
        let meat = ["chicken", "beef", "pork", "turkey", "bacon", "sausage", "fish", "salmon", "shrimp", "lamb", "meat"]
        let bakery = ["bread", "bun", "roll", "tortilla", "flour", "baguette"]
        let frozen = ["frozen", "ice cream"]
        let beverages = ["juice", "wine", "beer", "soda", "broth", "stock"]

        if produce.contains(where: { name.contains($0) }) { return .produce }
        if dairy.contains(where: { name.contains($0) }) { return .dairy }
        if meat.contains(where: { name.contains($0) }) { return .meat }
        if bakery.contains(where: { name.contains($0) }) { return .bakery }
        if frozen.contains(where: { name.contains($0) }) { return .frozen }
        if beverages.contains(where: { name.contains($0) }) { return .beverages }
        return .pantry
    }

    @discardableResult
    static func addIngredients(
        _ ingredients: [RecipeIngredient],
        to context: ModelContext,
        existing: [GroceryItem],
        note: String = "From meal plan"
    ) -> AddResult {
        var working = existing
        var result = AddResult()

        for ingredient in ingredients {
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if let match = working.first(where: {
                !$0.isChecked && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                let newQty = ingredient.quantity.trimmingCharacters(in: .whitespaces)
                if !newQty.isEmpty {
                    if match.quantity.isEmpty || match.quantity == "1" {
                        match.quantity = newQty
                    } else if !match.quantity.localizedCaseInsensitiveContains(newQty) {
                        match.quantity = "\(match.quantity) + \(newQty)"
                    }
                }
                result.updated += 1
                continue
            }

            let item = GroceryItem(
                name: name,
                quantity: ingredient.quantity.isEmpty ? "1" : ingredient.quantity,
                category: category(for: name),
                notes: note
            )
            context.insert(item)
            working.append(item)
            result.added += 1
        }

        return result
    }

    /// Builds / merges a grocery list from cookbook-linked meals in the given week.
    @discardableResult
    static func addIngredients(
        fromMeals meals: [MealPlan],
        recipes: [Recipe],
        to context: ModelContext,
        existing: [GroceryItem]
    ) -> AddResult {
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        var working = existing
        var result = AddResult()

        for meal in meals {
            guard let recipeID = meal.recipeID, let recipe = recipesByID[recipeID] else {
                result.mealsSkipped += 1
                continue
            }

            let ingredients = recipe.ingredients
            guard !ingredients.isEmpty else {
                result.mealsSkipped += 1
                continue
            }

            let mealResult = addIngredients(
                ingredients,
                to: context,
                existing: working,
                note: "From \(meal.recipeName)"
            )
            result.added += mealResult.added
            result.updated += mealResult.updated
            result.mealsUsed += 1

            // Keep working set current so later meals in the week merge quantities.
            working = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? working
        }

        return result
    }
}

// MARK: - TheMealDB decoding

private struct MealDBSearchResponse: Decodable {
    let meals: [MealDBMeal]?
}

private struct MealDBFilterResponse: Decodable {
    let meals: [MealDBFilterMeal]?
}

private struct MealDBFilterMeal: Decodable {
    let idMeal: String
    let strMeal: String
    let strMealThumb: String?
}

private struct MealDBMeal: Decodable {
    let idMeal: String
    let strMeal: String
    let strCategory: String?
    let strArea: String?
    let strInstructions: String?
    let strMealThumb: String?
    let strYoutube: String?
    let strSource: String?

    let strIngredient1: String?
    let strIngredient2: String?
    let strIngredient3: String?
    let strIngredient4: String?
    let strIngredient5: String?
    let strIngredient6: String?
    let strIngredient7: String?
    let strIngredient8: String?
    let strIngredient9: String?
    let strIngredient10: String?
    let strIngredient11: String?
    let strIngredient12: String?
    let strIngredient13: String?
    let strIngredient14: String?
    let strIngredient15: String?
    let strIngredient16: String?
    let strIngredient17: String?
    let strIngredient18: String?
    let strIngredient19: String?
    let strIngredient20: String?

    let strMeasure1: String?
    let strMeasure2: String?
    let strMeasure3: String?
    let strMeasure4: String?
    let strMeasure5: String?
    let strMeasure6: String?
    let strMeasure7: String?
    let strMeasure8: String?
    let strMeasure9: String?
    let strMeasure10: String?
    let strMeasure11: String?
    let strMeasure12: String?
    let strMeasure13: String?
    let strMeasure14: String?
    let strMeasure15: String?
    let strMeasure16: String?
    let strMeasure17: String?
    let strMeasure18: String?
    let strMeasure19: String?
    let strMeasure20: String?

    func parsedIngredients() -> [RecipeIngredient] {
        let pairs: [(String?, String?)] = [
            (strIngredient1, strMeasure1), (strIngredient2, strMeasure2),
            (strIngredient3, strMeasure3), (strIngredient4, strMeasure4),
            (strIngredient5, strMeasure5), (strIngredient6, strMeasure6),
            (strIngredient7, strMeasure7), (strIngredient8, strMeasure8),
            (strIngredient9, strMeasure9), (strIngredient10, strMeasure10),
            (strIngredient11, strMeasure11), (strIngredient12, strMeasure12),
            (strIngredient13, strMeasure13), (strIngredient14, strMeasure14),
            (strIngredient15, strMeasure15), (strIngredient16, strMeasure16),
            (strIngredient17, strMeasure17), (strIngredient18, strMeasure18),
            (strIngredient19, strMeasure19), (strIngredient20, strMeasure20),
        ]

        return pairs.compactMap { name, measure in
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedName.isEmpty else { return nil }
            let qty = measure?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return RecipeIngredient(name: trimmedName, quantity: qty)
        }
    }
}
