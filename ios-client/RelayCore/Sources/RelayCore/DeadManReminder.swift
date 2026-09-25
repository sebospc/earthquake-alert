import UserNotifications

/// Local notification that fires if the phone has not confirmed its registration for 8 days
/// (app force-quit with no wake-ups, server lost the token, broken token). Rescheduled after every
/// 201 with the same identifier, so it only ever fires when verification stopped. It is local,
/// so it fires with the app killed.
public enum DeadManReminder {
    public static let identifier = "dead-man"
    public static let interval: TimeInterval = 8 * 24 * 60 * 60

    public static func request() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Verifique sus alertas de sismo", bundle: .module)
        content.body = String(localized: "Abra la app para confirmar que sus alertas siguen activas.", bundle: .module)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
