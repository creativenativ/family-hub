import SwiftUI
import SwiftData

struct HouseholdNeedsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HouseholdNeed.createdAt, order: .reverse) private var needs: [HouseholdNeed]

    @State private var showingAdd = false
    @State private var hidePurchased = true

    private var visibleNeeds: [HouseholdNeed] {
        hidePurchased ? needs.filter { !$0.isPurchased } : needs
    }

    private var grouped: [(HouseholdNeedCategory, [HouseholdNeed])] {
        HouseholdNeedCategory.allCases.compactMap { category in
            let items = visibleNeeds.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        Group {
            if needs.isEmpty {
                ContentUnavailableView(
                    "No Household Needs",
                    systemImage: "house",
                    description: Text("Track toilet paper, cleaning supplies, light bulbs, and more")
                )
            } else if visibleNeeds.isEmpty {
                ContentUnavailableView(
                    "All Caught Up",
                    systemImage: "checkmark.circle",
                    description: Text("No open household needs. Toggle Show purchased to review bought items.")
                )
            } else {
                List {
                    ForEach(grouped, id: \.0) { category, items in
                        Section {
                            ForEach(items, id: \.id) { need in
                                HouseholdNeedRow(need: need)
                            }
                            .onDelete { offsets in
                                delete(items, at: offsets)
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
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Toggle(hidePurchased ? "Hide bought" : "Show bought", isOn: $hidePurchased)
                    .toggleStyle(.button)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddHouseholdNeedView()
        }
    }

    private func delete(_ items: [HouseholdNeed], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}

struct HouseholdNeedRow: View {
    @Bindable var need: HouseholdNeed

    private var priorityColor: Color {
        switch need.priority {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                need.isPurchased.toggle()
            } label: {
                Image(systemName: need.isPurchased ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(need.isPurchased ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(need.name)
                    .strikethrough(need.isPurchased)
                    .foregroundStyle(need.isPurchased ? .secondary : .primary)

                HStack(spacing: 8) {
                    if !need.quantity.isEmpty {
                        Text("Qty \(need.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(need.priority.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(priorityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor.opacity(0.15))
                        .clipShape(Capsule())

                    if need.estimatedCost > 0 {
                        Text(need.estimatedCost, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }
}

struct AddHouseholdNeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity = "1"
    @State private var category: HouseholdNeedCategory = .other
    @State private var priority: NeedPriority = .medium
    @State private var estimatedCost = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Quantity", text: $quantity)
                    Picker("Category", selection: $category) {
                        ForEach(HouseholdNeedCategory.allCases) { cat in
                            Label(cat.label, systemImage: cat.icon).tag(cat)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(NeedPriority.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    TextField("Estimated cost", text: $estimatedCost)
                        .keyboardType(.decimalPad)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Add Need")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let cost = Double(estimatedCost.replacingOccurrences(of: ",", with: ".")) ?? 0
        let need = HouseholdNeed(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            category: category,
            priority: priority,
            estimatedCost: cost,
            notes: notes
        )
        modelContext.insert(need)
        dismiss()
    }
}
