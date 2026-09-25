import Foundation

/// The text a push shows, in the phone's language (docs/ios-contract.md, "Localized text").
///
/// The gateway sends `title-loc-key`, `loc-key` and `loc-args` plus Spanish `title` and `body`.
/// iOS resolves the keys from the app's catalog, and shows the raw key ("ALERT_TITLE") when the
/// catalog lacks it. The NSE runs this to repair that case with the Spanish text, and to write the
/// magnitude with the phone's decimal separator.
public enum PushText {
    public static let magnitudeBodyKey = "ALERT_BODY_MAGNITUDE"

    /// - Parameter localizedFormat: the catalog's text for a key, or nil when the catalog lacks it.
    /// - Returns: nil when the push carries no loc-keys: leave it as it is.
    public static func resolve(userInfo: [AnyHashable: Any], locale: Locale,
                               localizedFormat: (String) -> String?) -> (title: String, body: String)? {
        guard let alert = (userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any],
              let titleKey = alert["title-loc-key"] as? String,
              let bodyKey = alert["loc-key"] as? String
        else { return nil }
        let spanishTitle = alert["title"] as? String ?? ""
        let spanishBody = alert["body"] as? String ?? ""
        var arguments = alert["loc-args"] as? [String] ?? []
        if bodyKey == magnitudeBodyKey, !arguments.isEmpty, let magnitude = (userInfo["magnitude"] as? NSNumber)?.doubleValue {
            arguments[0] = magnitude.formatted(.number.precision(.fractionLength(1)).locale(locale))
        }
        return (text(titleKey, [], fallback: spanishTitle, localizedFormat),
                text(bodyKey, arguments, fallback: spanishBody, localizedFormat))
    }

    private static func text(_ key: String, _ arguments: [String], fallback: String,
                             _ localizedFormat: (String) -> String?) -> String {
        guard let format = localizedFormat(key), format != key, placeholders(in: format) == arguments.count
        else { return fallback }
        return String(format: format, arguments: arguments)
    }

    /// Counts `%@` / `%1$@`. Any other specifier (`%d`, `%s`) would crash String(format:) with
    /// string arguments, so it counts as a mismatch and the Spanish text is used.
    static func placeholders(in format: String) -> Int {
        let withoutEscapes = format.replacingOccurrences(of: "%%", with: "")
        let all = withoutEscapes.matches(of: /%/).count
        let objects = withoutEscapes.matches(of: /%(\d+\$)?@/).count
        return all == objects ? objects : -1
    }
}
