import Foundation
import SwiftData
import UIKit

struct RecipeIngredient: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var quantity: String

    init(id: UUID = UUID(), name: String, quantity: String = "") {
        self.id = id
        self.name = name
        self.quantity = quantity
    }

    var displayLine: String {
        let trimmedQty = quantity.trimmingCharacters(in: .whitespaces)
        if trimmedQty.isEmpty { return name }
        return "\(trimmedQty) \(name)"
    }
}

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var instructions: String = ""
    var sourceURL: String = ""
    var imageURL: String = ""
    var imageData: Data?
    var servings: Int = 4
    var externalID: String = ""
    var ingredientsData: Data = Data()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var cloudSynced: Bool = false

    init(
        name: String,
        summary: String = "",
        instructions: String = "",
        sourceURL: String = "",
        imageURL: String = "",
        imageData: Data? = nil,
        servings: Int = 4,
        externalID: String = "",
        ingredients: [RecipeIngredient] = []
    ) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.imageData = imageData
        self.servings = servings
        self.externalID = externalID
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.cloudSynced = false
    }

    func touchForSync() {
        modifiedAt = Date()
    }

    var ingredients: [RecipeIngredient] {
        get {
            (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? []
        }
        set {
            ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            touchForSync()
        }
    }

    var displayImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}
