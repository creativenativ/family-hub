import SwiftUI

enum HouseholdSection: String, CaseIterable, Identifiable {
    case budget
    case groceries
    case needs
    case wishlist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .budget: "Budget"
        case .groceries: "Grocery"
        case .needs: "Needs"
        case .wishlist: "Wish List"
        }
    }

    var icon: String {
        switch self {
        case .budget: "dollarsign.circle.fill"
        case .groceries: "cart.fill"
        case .needs: "house.fill"
        case .wishlist: "gift.fill"
        }
    }
}

struct HouseholdView: View {
    @State private var section: HouseholdSection = .groceries

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(HouseholdSection.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                Group {
                    switch section {
                    case .budget:
                        BudgetView()
                    case .groceries:
                        GroceryListView()
                    case .needs:
                        HouseholdNeedsView()
                    case .wishlist:
                        WishListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Household")
        }
    }
}

#Preview {
    HouseholdView()
}
