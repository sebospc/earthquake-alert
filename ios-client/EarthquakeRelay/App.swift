import RelayCore
import SwiftUI
import UserNotifications

@main
struct EarthquakeRelayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: appDelegate.model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appDelegate.model.becameActive() }
        }
    }
}

/// Owns the model so it exists on background launches too (location wake-ups have no scene).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor lazy var model = AppModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Store.start()
        MainActor.assumeIsolated { model.launched() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { model.tokenArrived(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token means not registered: the screen already says so until a 201 arrives.
        print("APNs registration failed: \(error.localizedDescription)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        // The extension logged it too; the app's own line says it was seen in the foreground.
        if let log = AppGroup.pushArrivalsFile {
            PushArrivalLog.append(PushArrival(userInfo: notification.request.content.userInfo, receivedAt: Date(),
                                              source: .app, appState: .foreground), to: log)
        }
        let alert = EarthquakeAlert(displayed: notification.request.content)
        await MainActor.run { model.received(alert) }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let alert = EarthquakeAlert(displayed: response.notification.request.content)
        await MainActor.run { model.received(alert) }
    }
}

extension EarthquakeAlert {
    /// The alert screen shows what the notification showed: already in the phone's language (iOS
    /// and the NSE resolved the loc-keys), not the payload's Spanish body.
    nonisolated init?(displayed content: UNNotificationContent) {
        self.init(userInfo: content.userInfo)
        if !content.body.isEmpty { body = content.body }
    }
}
