import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlan.date) private var meals: [MealPlan]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query private var groceryItems: [GroceryItem]
    @Query(sort: \FavoriteWeeklyMealPlan.name) private var favoritePlans: [FavoriteWeeklyMealPlan]

    @State private var selectedWeek = Date()
    @State private var showingAddMeal = false
    @State private var addMealDate = Date()
    @State private var addMealType: MealType = .dinner
    @State private var groceryResultMessage: String?
    @State private var showingGroceryResult = false
    @State private var showingSaveFavorite = false
    @State private var showingFavorites = false
    @State private var statusMessage: String?
    @State private var showingStatus = false

    private var weekDays: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: selectedWeek.startOfWeek)
        }
    }

    private var mealsThisWeek: [MealPlan] {
        meals.filter { meal in
            weekDays.contains { meal.date.isSameDay(as: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekNavigator

            List {
                ForEach(weekDays, id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(MealType.allCases) { mealType in
                            MealSlotRow(
                                day: day,
                                mealType: mealType,
                                meal: meal(for: day, type: mealType),
                                onSelectEmpty: {
                                    addMealDate = day
                                    addMealType = mealType
                                    showingAddMeal = true
                                },
                                onDelete: deleteMeal
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addMealDate = selectedWeek
                    addMealType = .dinner
                    showingAddMeal = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        generateGroceryListForWeek()
                    } label: {
                        Label("Grocery list from this week", systemImage: "cart.badge.plus")
                    }
                    .disabled(mealsThisWeek.isEmpty)

                    Divider()

                    Button {
                        showingSaveFavorite = true
                    } label: {
                        Label("Save week as favorite", systemImage: "star")
                    }
                    .disabled(mealsThisWeek.isEmpty)

                    Button {
                        showingFavorites = true
                    } label: {
                        Label(
                            favoritePlans.isEmpty ? "Favorite plans" : "Favorite plans (\(favoritePlans.count))",
                            systemImage: "star.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddMeal) {
            AddMealView(selectedDate: addMealDate, initialMealType: addMealType)
        }
        .sheet(isPresented: $showingSaveFavorite) {
            SaveFavoriteWeeklyMealPlanView(
                meals: mealsThisWeek,
                weekStart: selectedWeek
            ) { message in
                statusMessage = message
                showingStatus = true
            }
        }
        .sheet(isPresented: $showingFavorites) {
            FavoriteWeeklyMealPlansView(weekStart: selectedWeek) { message in
                statusMessage = message
                showingStatus = true
            }
        }
        .alert("Grocery List", isPresented: $showingGroceryResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(groceryResultMessage ?? "")
        }
        .alert("Meal Plan", isPresented: $showingStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                selectedWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(weekRangeLabel)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                selectedWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private func meal(for day: Date, type: MealType) -> MealPlan? {
        meals.first { $0.date.isSameDay(as: day) && $0.mealType == type }
    }

    private func deleteMeal(_ meal: MealPlan) {
        modelContext.delete(meal)
    }

    private func generateGroceryListForWeek() {
        let weekMeals = mealsThisWeek
        guard !weekMeals.isEmpty else {
            groceryResultMessage = "Add some meals to this week first."
            showingGroceryResult = true
            return
        }

        let result = GroceryIngredientMapper.addIngredients(
            fromMeals: weekMeals,
            recipes: recipes,
            to: modelContext,
            existing: groceryItems
        )

        if result.mealsUsed == 0 {
            if result.mealsSkipped > 0 {
                groceryResultMessage = "This week’s meals don’t have cookbook ingredients yet. Pick meals from Cookbook recipes (or add ingredients to those recipes), then try again."
            } else {
                groceryResultMessage = "No ingredients found for this week’s meals."
            }
        } else {
            var parts: [String] = []
            if result.added > 0 {
                parts.append("added \(result.added) new item\(result.added == 1 ? "" : "s")")
            }
            if result.updated > 0 {
                parts.append("updated quantities on \(result.updated)")
            }
            let summary = parts.joined(separator: " and ")
            var message = "From \(result.mealsUsed) meal\(result.mealsUsed == 1 ? "" : "s"), \(summary). Find the list under Household → Grocery."
            if result.mealsSkipped > 0 {
                message += " \(result.mealsSkipped) custom meal\(result.mealsSkipped == 1 ? "" : "s") skipped (no recipe ingredients)."
            }
            groceryResultMessage = message
        }

        showingGroceryResult = true
    }
}

struct MealSlotRow: View {
    let day: Date
    let mealType: MealType
    let meal: MealPlan?
    let onSelectEmpty: () -> Void
    let onDelete: (MealPlan) -> Void

    var body: some View {
        HStack {
            Label(mealType.label, systemImage: mealType.icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            if let meal {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.recipeName)
                        .font(.body)
                    if !meal.notes.isEmpty {
                        Text(meal.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if meal.recipeID != nil {
                        Text("Cookbook recipe")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Button(action: onSelectEmpty) {
                    Text("Add meal")
                        .font(.subheadline)
                        .foregroundStyle(Color.themeAccent)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            if let meal {
                Button(role: .destructive) {
                    onDelete(meal)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
