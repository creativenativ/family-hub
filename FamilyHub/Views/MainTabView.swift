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

    @State private var selectedTab: MainTab = Self.initialTab

    /// Debug builds accept `-startTab tribe` (or calendar, meals, household, chores) at launch.
    private static var initialTab: MainTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-startTab"), index + 1 < args.count {
            switch args[index + 1] {
            case "meals": return .meals
            case "household": return .household
            case "chores": return .chores
            case "tribe": return .family
            default: break
            }
        }
        #endif
        return .calendar
    }
    @State private var showingNotifications = false

    private var unreadTribeCount: Int { memberships.reduce(0) { $0 + $1.unreadCount } }
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
                    .badge(unreadTribeCount)
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
        .task(id: memberships.map(\.id)) {
            #if DEBUG
            DemoTribes.seedIfRequested(in: modelContext)
            #endif
            FamilyMembership.migrateHomeIfNeeded(in: modelContext)
            guard !memberships.isEmpty else { return }
            _ = try? await FamilySyncService.shared.syncAll(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !memberships.isEmpty else { return }
            FamilySyncService.shared.scheduleSync(modelContext: modelContext, delayNanoseconds: 500_000_000)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard (notification.object as? ModelContext) === modelContext, !memberships.isEmpty else { return }
            FamilySyncService.shared.noteLocalSave(modelContext: modelContext)
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
