import UserNotifications

public enum NotificationPermission {
    /// Never `.provisional`: provisional notifications arrive quietly, the opposite of an alert.
    /// `.criticalAlert` only once Apple grants the entitlement (build flag CRITICAL_ALERTS).
    public static func options(criticalAlertsEntitled: Bool) -> UNAuthorizationOptions {
        criticalAlertsEntitled ? [.alert, .sound, .badge, .criticalAlert] : [.alert, .sound, .badge]
    }

    /// Screen permission from the system settings. Time-sensitive off is not "denied": alerts still
    /// arrive, only Focus may silence them, which the screen warns about separately.
    public static func permission(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .ephemeral: .granted
        // Provisional is quiet delivery: for an earthquake alert that is as bad as off.
        case .denied, .provisional: .denied
        @unknown default: .denied
        }
    }
}
