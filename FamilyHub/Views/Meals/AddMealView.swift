import SwiftUI
import SwiftData

struct AddMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query private var groceryItems: [GroceryItem]
    @Query private var meals: [MealPlan]

    @State private var date: Date
    @State private var mealType: MealType
    @State private var recipeName = ""
    @State private var notes = ""
    @State private var servings = 4
    @State private var selectedRecipe: Recipe?
    @State private var addIngredientsToGrocery = true
    @State private var source: MealSource = .cookbook

    enum MealSource: String, CaseIterable, Identifiable {
        case cookbook
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cookbook: "Cookbook"
            case .custom: "Custom"
            }
        }
    }

    init(selectedDate: Date, initialMealType: MealType = .dinner) {
        _date = State(initialValue: selectedDate)
        _mealType = State(initialValue: initialMealType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Source") {
                    Picker("Source", selection: $source) {
                        ForEach(MealSource.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: source) { _, newValue in
                        if newValue == .custom {
                            selectedRecipe = nil
                        }
                    }
                }

                if source == .cookbook {
                    Section {
                        if recipes.isEmpty {
                            Text("No cookbook recipes yet. Save recipes from the Cookbook tab first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Recipe", selection: $selectedRecipe) {
                                Text("Choose a recipe").tag(nil as Recipe?)
                                ForEach(recipes, id: \.id) { recipe in
                                    Text(recipe.name).tag(recipe as Recipe?)
                                }
                            }
                            .onChange(of: selectedRecipe) { _, recipe in
                                guard let recipe else { return }
                                recipeName = recipe.name
                                servings = recipe.servings
                                notes = recipe.summary
                            }
                        }

                        if let selectedRecipe {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(selectedRecipe.ingredients.count) ingredients")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(selectedRecipe.ingredients.prefix(6)) { ingredient in
                                    Text("· \(ingredient.displayLine)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if selectedRecipe.ingredients.count > 6 {
                                    Text("+ \(selectedRecipe.ingredients.count - 6) more")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Toggle("Add ingredients to grocery list", isOn: $addIngredientsToGrocery)
                        }
                    } header: {
                        Text("Cookbook Recipe")
                    } footer: {
                        Text("Choosing a cookbook recipe can automatically add its ingredients to Household → Grocery.")
                    }
                } else {
                    Section("What") {
                        TextField("Recipe or meal name", text: $recipeName)
                        Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                    }

                    Section("Notes") {
                        TextField("Ingredients, prep notes…", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                if source == .cookbook, selectedRecipe != nil {
                    Section("Servings") {
                        Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                    }
                }
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveMeal() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if source == .cookbook, selectedRecipe == nil, let first = recipes.first {
                    // leave unselected so user chooses intentionally
                    _ = first
                }
            }
        }
    }

    private var canSave: Bool {
        if source == .cookbook {
            return selectedRecipe != nil
        }
        return !recipeName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveMeal() {
        let name: String
        let recipeID: UUID?
        let mealNotes: String

        if source == .cookbook, let recipe = selectedRecipe {
            name = recipe.name
            recipeID = recipe.id
            mealNotes = notes.isEmpty ? recipe.summary : notes

            if addIngredientsToGrocery {
                GroceryIngredientMapper.addIngredients(
                    recipe.ingredients,
                    to: modelContext,
                    existing: groceryItems
                )
            }
        } else {
            name = recipeName.trimmingCharacters(in: .whitespaces)
            recipeID = nil
            mealNotes = notes
        }

        // Replace existing meal in the same slot if present
        let day = date.startOfDay
        if let existing = meals.first(where: {
            $0.date.isSameDay(as: day) && $0.mealType == mealType
        }) {
            modelContext.delete(existing)
        }

        let meal = MealPlan(
            date: date,
            mealType: mealType,
            recipeName: name,
            notes: mealNotes,
            servings: servings,
            recipeID: recipeID
        )
        modelContext.insert(meal)
        dismiss()
    }
}
