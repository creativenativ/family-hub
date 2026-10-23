import SwiftUI

enum MealsSection: String, CaseIterable, Identifiable {
    case plan
    case cookbook

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plan: "Meal Plan"
        case .cookbook: "Cookbook"
        }
    }
}

struct MealsHubView: View {
    @State private var section: MealsSection = .plan

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(MealsSection.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                Group {
                    switch section {
                    case .plan:
                        MealPlanView()
                    case .cookbook:
                        CookbookView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Meals")
        }
    }
}

#Preview {
    MealsHubView()
}
