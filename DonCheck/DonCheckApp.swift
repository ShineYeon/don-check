import SwiftUI
import UserNotifications

@main
struct DonCheckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ChecklistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: .checklistDidChange)) { _ in
                    store.reload()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationScheduler.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NotificationScheduler.completeAction,
              let itemIDString = response.notification.request.content.userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: itemIDString),
              let cycleKey = response.notification.request.content.userInfo["cycleKey"] as? String else {
            return
        }

        let data = ChecklistRepository.shared.setCompletion(itemID: itemID, cycleKey: cycleKey, isComplete: true)
        await NotificationScheduler.cancel(itemID: itemID, cycleKey: cycleKey)
        await NotificationScheduler.rescheduleAll(data)
        await LiveActivityManager.refresh(data)
        NotificationCenter.default.post(name: .checklistDidChange, object: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }
}

extension Notification.Name {
    static let checklistDidChange = Notification.Name("checklistDidChange")
}
