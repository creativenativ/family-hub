import SwiftUI
import SwiftData
import UserNotifications

@main
struct FamilyHubApp: App {
    @UIApplicationDelegateAdaptor(FamilyHubAppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Loads the saved theme and styles UIKit pieces (tab badges) before any view exists.
        _ = ThemeStore.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FamilyMember.self,
            CalendarEvent.self,
            MealPlan.self,
            GroceryItem.self,
            Chore.self,
            VoiceMemo.self,
            PendingEmailImport.self,
            BudgetItem.self,
            BudgetExpense.self,
            IncomeSource.self,
            RecurringBill.self,
            HouseholdNeed.self,
            WishListItem.self,
            Recipe.self,
            FamilyMembership.self,
            FavoriteWeeklyMealPlan.self,
            BoardNote.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.danielschwartzel.familyhub")
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
