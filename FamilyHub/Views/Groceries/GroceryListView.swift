import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryItem.createdAt, order: .reverse) private var items: [GroceryItem]
    @Query(sort: \MealPlan.date) private var meals: [MealPlan]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var showingAddItem = false
    @State private var hideChecked = false
    @State private var groceryResultMessage: String?
    @State private var showingGroceryResult = false

    private var groupedItems: [(GroceryCategory, [GroceryItem])] {
        let filtered = hideChecked ? items.filter { !$0.isChecked } : items
        return GroceryCategory.allCases.compactMap { category in
            let categoryItems = filtered.filter { $0.category == category }
            return categoryItems.isEmpty ? nil : (category, categoryItems)
        }
    }

    private var checkedCount: Int {
        items.filter(\.isChecked).count
    }

    private var mealsThisWeek: [MealPlan] {
        let weekStart = Date().startOfWeek
        let weekDays = (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: weekStart)
        }
        return meals.filter { meal in
            weekDays.contains { meal.date.isSameDay(as: $0) }
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Empty Grocery List", systemImage: "cart")
                } description: {
                    Text("Add items manually, or build a list from this week’s meal plan.")
                } actions: {
                    Button("From this week’s meals") {
                        generateFromThisWeeksMeals()
                    }
                    Button("Add item") { showingAddItem = true }
                }
            } else {
                List {
                    ForEach(groupedItems, id: \.0) { category, categoryItems in
                        Section {
                            ForEach(categoryItems, id: \.id) { item in
                                GroceryItemRow(item: item)
                            }
                            .onDelete { offsets in
                                deleteItems(categoryItems: categoryItems, at: offsets)
                            }
                        } header: {
                            Label(category.label, systemImage: category.icon)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        generateFromThisWeeksMeals()
                    } label: {
                        Label("Add from this week’s meals", systemImage: "cart.badge.plus")
                    }

                    Toggle("Hide checked items", isOn: $hideChecked)
                    if checkedCount > 0 {
                        Button("Clear checked (\(checkedCount))", role: .destructive) {
                            clearChecked()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView()
        }
        .alert("Grocery List", isPresented: $showingGroceryResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(groceryResultMessage ?? "")
        }
    }

    private func generateFromThisWeeksMeals() {
        let weekMeals = mealsThisWeek
        guard !weekMeals.isEmpty else {
            groceryResultMessage = "No meals planned for this week yet. Add some under Meals → Plan."
            showingGroceryResult = true
            return
        }

        let result = GroceryIngredientMapper.addIngredients(
            fromMeals: weekMeals,
            recipes: recipes,
            to: modelContext,
            existing: items
        )

        if result.mealsUsed == 0 {
            groceryResultMessage = "This week’s meals don’t have cookbook ingredients yet. Use Cookbook recipes on the meal plan, then try again."
        } else {
            var parts: [String] = []
            if result.added > 0 {
                parts.append("added \(result.added) new item\(result.added == 1 ? "" : "s")")
            }
            if result.updated > 0 {
                parts.append("updated \(result.updated)")
            }
            groceryResultMessage = "From \(result.mealsUsed) meal\(result.mealsUsed == 1 ? "" : "s"), \(parts.joined(separator: " and "))."
            if result.mealsSkipped > 0 {
                groceryResultMessage? += " \(result.mealsSkipped) custom meal\(result.mealsSkipped == 1 ? "" : "s") skipped."
            }
        }
        showingGroceryResult = true
    }

    private func deleteItems(categoryItems: [GroceryItem], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(categoryItems[index])
        }
    }

    private func clearChecked() {
        for item in items where item.isChecked {
            modelContext.delete(item)
        }
    }
}

struct GroceryItemRow: View {
    @Bindable var item: GroceryItem

    var body: some View {
        HStack {
            Button {
                item.isChecked.toggle()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)

                if !item.quantity.isEmpty && item.quantity != "1" {
                    Text("Qty: \(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        GroceryListView()
    }
    .modelContainer(for: GroceryItem.self, inMemory: true)
}
