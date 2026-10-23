import SwiftUI
import SwiftData

struct WishListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WishListItem.createdAt, order: .reverse) private var items: [WishListItem]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]

    @State private var showingAdd = false
    @State private var hidePurchased = true

    private var visibleItems: [WishListItem] {
        hidePurchased ? items.filter { !$0.isPurchased } : items
    }

    private var totalWishValue: Double {
        visibleItems.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Wish List Empty",
                    systemImage: "gift",
                    description: Text("Save things the tribe wants — gifts, upgrades, and someday purchases")
                )
            } else if visibleItems.isEmpty {
                ContentUnavailableView(
                    "All Purchased",
                    systemImage: "checkmark.circle",
                    description: Text("Toggle Show purchased to see bought wish list items.")
                )
            } else {
                List {
                    Section {
                        HStack {
                            Text("Open wishes")
                            Spacer()
                            Text("\(visibleItems.count)")
                                .foregroundStyle(.secondary)
                        }
                        if totalWishValue > 0 {
                            HStack {
                                Text("Estimated total")
                                Spacer()
                                Text(totalWishValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Wishes") {
                        ForEach(visibleItems, id: \.id) { item in
                            WishListItemRow(item: item)
                        }
                        .onDelete(perform: deleteVisible)
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
            AddWishListItemView(members: members)
        }
    }

    private func deleteVisible(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleItems[index])
        }
    }
}

struct WishListItemRow: View {
    @Bindable var item: WishListItem

    private var priorityColor: Color {
        switch item.priority {
        case .high: .pink
        case .medium: .purple
        case .low: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                item.isPurchased.toggle()
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isPurchased ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .strikethrough(item.isPurchased)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)

                HStack(spacing: 8) {
                    if item.price > 0 {
                        Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.priority.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(priorityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor.opacity(0.15))
                        .clipShape(Capsule())

                    if let member = item.forMember {
                        HStack(spacing: 4) {
                            MemberAvatar(member: member, size: 16, showColorRing: false)
                            Text(member.name)
                                .font(.caption2)
                                .foregroundStyle(member.color)
                        }
                    }
                }

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }
}

struct AddWishListItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let members: [FamilyMember]

    @State private var name = ""
    @State private var price = ""
    @State private var priority: WishPriority = .medium
    @State private var notes = ""
    @State private var link = ""
    @State private var selectedMember: FamilyMember?

    var body: some View {
        NavigationStack {
            Form {
                Section("Wish") {
                    TextField("Name", text: $name)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    Picker("Priority", selection: $priority) {
                        ForEach(WishPriority.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }

                if !members.isEmpty {
                    Section("For") {
                        Picker("Tribe Member", selection: $selectedMember) {
                            Text("Whole tribe").tag(nil as FamilyMember?)
                            ForEach(members, id: \.id) { member in
                                Text(member.name).tag(member as FamilyMember?)
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Link (optional)", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add Wish")
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
        let amount = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        let item = WishListItem(
            name: name.trimmingCharacters(in: .whitespaces),
            price: amount,
            priority: priority,
            notes: notes,
            link: link,
            forMember: selectedMember
        )
        modelContext.insert(item)
        dismiss()
    }
}
