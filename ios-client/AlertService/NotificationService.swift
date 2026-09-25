import RelayCore
import UserNotifications

/// Runs for every push with `mutable-content: 1`, even with the app force-quit. It logs the
/// arrival time, then shows the text in the phone's language (`PushText`). If this fails or times
/// out, iOS shows the push untouched, so it can add information but never lose an alert.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // Log first: after contentHandler iOS may end the extension before the write lands.
        // A crash here still shows the original push, so this cannot lose an alert.
        if let log = AppGroup.pushArrivalsFile {
            PushArrivalLog.append(PushArrival(userInfo: request.content.userInfo, receivedAt: Date(), source: .nse, appState: .unknown), to: log)
        }
        // iOS shows the raw key ("ALERT_TITLE") when the catalog lacks it; PushText swaps in the
        // payload's Spanish text then, and writes the magnitude with the phone's decimal separator.
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let text = PushText.resolve(userInfo: request.content.userInfo, locale: .current, localizedFormat: { key in
                  let value = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                  return value == key ? nil : value
              })
        else { return contentHandler(request.content) }
        content.title = text.title
        content.body = text.body
        contentHandler(content)
    }
}
