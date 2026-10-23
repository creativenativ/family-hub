import SwiftUI
import SwiftData

private enum MainTab: Hashable {
    case calendar, meals, household, chores, family
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(
        filter: #Predicate<PendingEmailImport> { $0.statusRaw == "pending" }
    ) private var pendingImports: [PendingEmailImport]
    @Query private var memberships: [FamilyMembership]

    @State private var selectedTab: MainTab = .calendar
    @State private var showingNotifications = false

    private var membership: FamilyMembership? { memberships.first }
    private var showsNotificationBell: Bool { selectedTab == .calendar }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TabView(selection: $selectedTab) {
                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(MainTab.calendar)

                MealsHubView()
                    .tabItem {
                        Label("Meals", systemImage: "fork.knife")
                    }
                    .tag(MainTab.meals)

                HouseholdView()
                    .tabItem {
                        Label("Household", systemImage: "house.fill")
                    }
                    .tag(MainTab.household)

                ChoresView()
                    .tabItem {
                        Label("Chores", systemImage: "checklist")
                    }
                    .tag(MainTab.chores)

                FamilyMembersView()
                    .tabItem {
                        Label("Tribe", systemImage: "person.3.fill")
                    }
                    .tag(MainTab.family)
            }

            if showsNotificationBell {
                VStack(alignment: .leading, spacing: 0) {
                    NotificationsLaunchButton(pendingCount: pendingImports.count) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            showingNotifications.toggle()
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.top, 4)

                    Spacer()
                }
                .safeAreaPadding(.top, 4)
                .zIndex(1)

                NotificationsPanel(isPresented: $showingNotifications)
                    .zIndex(2)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .calendar, showingNotifications {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    showingNotifications = false
                }
            }
        }
        .task(id: membership?.id) {
            guard let membership else { return }
            _ = try? await FamilySyncService.shared.syncNow(membership: membership, modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let membership else { return }
            FamilySyncService.shared.scheduleSync(
                membership: membership,
                modelContext: modelContext,
                delayNanoseconds: 500_000_000
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard (notification.object as? ModelContext) === modelContext else { return }
            FamilySyncService.shared.noteLocalSave(membership: membership, modelContext: modelContext)
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [
            FamilyMember.self,
            CalendarEvent.self,
            MealPlan.self,
            GroceryItem.self,
            Chore.self,
            PendingEmailImport.self,
            BudgetItem.self,
            HouseholdNeed.self,
            WishListItem.self,
            FamilyMembership.self,
            Recipe.self,
            FavoriteWeeklyMealPlan.self,
        ], inMemory: true)
}
