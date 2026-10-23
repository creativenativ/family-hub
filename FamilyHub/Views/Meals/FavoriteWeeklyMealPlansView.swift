import SwiftUI
import SwiftData

struct FavoriteWeeklyMealPlansView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteWeeklyMealPlan.name) private var favorites: [FavoriteWeeklyMealPlan]
    @Query(sort: \MealPlan.date) private var meals: [MealPlan]

    let weekStart: Date
    var onApplied: ((String) -> Void)?

    @State private var favoritePendingApply: FavoriteWeeklyMealPlan?
    @State private var showingReplaceConfirm = false

    private var weekDays: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: weekStart.startOfWeek)
        }
    }

    private var mealsThisWeek: [MealPlan] {
        meals.filter { meal in
            weekDays.contains { meal.date.isSameDay(as: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorite Plans",
                        systemImage: "star",
                        description: Text("Save a week from the meal plan to reuse it later.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(favorites, id: \.id) { favorite in
                                Button {
                                    requestApply(favorite)
                                } label: {
                                    FavoritePlanRow(favorite: favorite)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteFavorites)
                        } footer: {
                            Text("Tap a plan to fill the week you’re viewing (\(weekRangeLabel)). Existing meals in those slots will be replaced.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Favorite Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Replace this week’s meals?",
                isPresented: $showingReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Apply favorite plan", role: .destructive) {
                    if let favorite = favoritePendingApply {
                        apply(favorite)
                    }
                }
                Button("Cancel", role: .cancel) {
                    favoritePendingApply = nil
                }
            } message: {
                if let favorite = favoritePendingApply {
                    Text("“\(favorite.name)” will replace \(mealsThisWeek.count) meal\(mealsThisWeek.count == 1 ? "" : "s") already on this week.")
                }
            }
        }
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "this week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private func requestApply(_ favorite: FavoriteWeeklyMealPlan) {
        if mealsThisWeek.isEmpty {
            apply(favorite)
        } else {
            favoritePendingApply = favorite
            showingReplaceConfirm = true
        }
    }

    private func apply(_ favorite: FavoriteWeeklyMealPlan) {
        let count = favorite.apply(
            toWeekStarting: weekStart.startOfWeek,
            replacing: mealsThisWeek,
            in: modelContext
        )
        onApplied?("Applied “\(favorite.name)” · \(count) meal\(count == 1 ? "" : "s")")
        favoritePendingApply = nil
        dismiss()
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
    }
}

private struct FavoritePlanRow: View {
    @Bindable var favorite: FavoriteWeeklyMealPlan

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(favorite.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(favorite.mealCount) meal\(favorite.mealCount == 1 ? "" : "s") · \(favorite.previewSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let lastUsedAt = favorite.lastUsedAt {
                    Text("Last used \(lastUsedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct SaveFavoriteWeeklyMealPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let meals: [MealPlan]
    let weekStart: Date
    var onSaved: ((String) -> Void)?

    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !meals.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Favorite plan name")
                } footer: {
                    Text("Saves \(meals.count) meal\(meals.count == 1 ? "" : "s") from this week so you can apply them to any future week.")
                }

                Section("Included meals") {
                    ForEach(meals.sorted(by: mealSort), id: \.id) { meal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.recipeName)
                                .font(.body.weight(.medium))
                            Text("\(weekdayLabel(for: meal.date)) · \(meal.mealType.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if name.isEmpty {
                    name = suggestedName()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func mealSort(_ lhs: MealPlan, _ rhs: MealPlan) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.mealTypeRaw < rhs.mealTypeRaw
    }

    private func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private func suggestedName() -> String {
        let dinners = meals.filter { $0.mealType == .dinner }.map(\.recipeName)
        if let first = dinners.first {
            return dinners.count > 1 ? "\(first) week" : "\(first) plan"
        }
        if let first = meals.first?.recipeName {
            return "\(first) week"
        }
        return "Favorite week"
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slots = FavoriteWeeklyMealPlan.slots(from: meals, weekStart: weekStart.startOfWeek)
        guard !slots.isEmpty else { return }
        let favorite = FavoriteWeeklyMealPlan(name: trimmed, slots: slots)
        modelContext.insert(favorite)
        onSaved?("Saved “\(trimmed)”")
        dismiss()
    }
}
