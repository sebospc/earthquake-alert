import SwiftUI
import UserNotifications

@main
struct EarthquakeRelayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NotificationStore.shared

    var body: some Scene {
        WindowGroup {
            NavigationView {
                List {
                    Section("Estado") {
                        Text(store.authorization)
                        Text(store.deviceToken.isEmpty
                             ? "Token APNs: pendiente"
                             : "Token APNs: …\(store.deviceToken.suffix(12))")
                    }

                    Section("Acciones") {
                        Button("Autorizar notificaciones") {
                            appDelegate.requestAuthorization(includeCritical: false)
                        }
                        Button("Copiar token APNs") {
                            UIPasteboard.general.string = store.deviceToken
                        }
                    }

                    Section("Historial local") {
                        if store.events.isEmpty {
                            Text("Sin notificaciones recibidas")
                        }
                        ForEach(store.events.reversed()) { event in
                            VStack(alignment: .leading) {
                                Text(event.title).bold()
                                Text(event.body)
                                Text(event.receivedAt.formatted())
                                    .font(.caption)
                            }
                        }
                    }

                    Section("Limitación") {
                        Text("Laboratorio complementario. APNs no garantiza entrega. Critical Alerts no está habilitado hasta que Apple apruebe el entitlement.")
                            .font(.footnote)
                    }
                }
                .navigationTitle("Earthquake Relay")
            }
            .onAppear { appDelegate.refreshAuthorizationStatus() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
        return true
    }

    func requestAuthorization(includeCritical: Bool) {
        var options: UNAuthorizationOptions = [.alert, .badge, .sound]
        if #available(iOS 15.0, *) {
            options.insert(.providesAppNotificationSettings)
        }
        if includeCritical {
            options.insert(.criticalAlert)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            DispatchQueue.main.async {
                NotificationStore.shared.authorization = error.map {
                    "Error: \($0.localizedDescription)"
                } ?? (granted ? "Autorizadas" : "Denegadas")
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                NotificationStore.shared.authorization =
                    "Notificaciones: \(settings.authorizationStatus.label); " +
                    "Critical: \(settings.criticalAlertSetting.label)"
                if settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationStore.shared.deviceToken =
            deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationStore.shared.authorization =
            "Falló registro APNs: \(error.localizedDescription)"
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        NotificationStore.shared.record(notification.request.content)
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationStore.shared.record(response.notification.request.content)
    }
}

struct ReceivedEvent: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let receivedAt: Date
}

final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()
    @Published var authorization = "Consultando…"
    @Published var deviceToken = ""
    @Published private(set) var events: [ReceivedEvent] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: "received-events"),
           let decoded = try? JSONDecoder().decode([ReceivedEvent].self, from: data) {
            events = decoded
        }
    }

    func record(_ content: UNNotificationContent) {
        DispatchQueue.main.async {
            let eventID = content.userInfo["event_id"] as? String ?? UUID().uuidString
            guard !self.events.contains(where: { $0.id == eventID }) else { return }
            self.events.append(ReceivedEvent(
                id: eventID,
                title: content.title,
                body: content.body,
                receivedAt: Date()
            ))
            self.events = Array(self.events.suffix(100))
            if let data = try? JSONEncoder().encode(self.events) {
                UserDefaults.standard.set(data, forKey: "received-events")
            }
        }
    }
}

private extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: return "no solicitadas"
        case .denied: return "denegadas"
        case .authorized: return "autorizadas"
        case .provisional: return "provisionales"
        case .ephemeral: return "efímeras"
        @unknown default: return "desconocido"
        }
    }
}

private extension UNNotificationSetting {
    var label: String {
        switch self {
        case .notSupported: return "no soportado"
        case .disabled: return "deshabilitado"
        case .enabled: return "habilitado"
        @unknown default: return "desconocido"
        }
    }
}
