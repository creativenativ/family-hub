import SwiftUI
import SwiftData

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity = "1"
    @State private var category: GroceryCategory = .other
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Quantity", text: $quantity)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(GroceryCategory.allCases) { cat in
                            Label(cat.label, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveItem() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveItem() {
        let item = GroceryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            category: category,
            notes: notes
        )
        modelContext.insert(item)
        dismiss()
    }
}
