import Foundation

/// Pro (Watch app, widget, quake history). Never gates an alert: alerts are free for everyone.
/// The app writes the expiry to the App Group; the widget and the Watch read it, so a lapsed
/// subscription turns off by the clock even before the app runs again.
public enum ProEntitlement {
    /// Placeholders until the products exist in App Store Connect; must match Pro.storekit.
    public static let productIDs: Set<String> = ["pro.monthly", "pro.yearly"]
    static let expiryKey = "pro-expires-at"

    /// What the app keeps from each verified StoreKit transaction.
    public struct Purchase: Sendable {
        public let productID: String
        public let expiresAt: Date?
        public let revokedAt: Date?

        public init(productID: String, expiresAt: Date?, revokedAt: Date?) {
            self.productID = productID
            self.expiresAt = expiresAt
            self.revokedAt = revokedAt
        }
    }

    /// Latest expiry among the Pro purchases; nil means no Pro. A refunded purchase counts as none.
    public static func expiry(of purchases: [Purchase]) -> Date? {
        purchases
            .filter { productIDs.contains($0.productID) && $0.revokedAt == nil }
            .compactMap(\.expiresAt)
            .max()
    }

    public static func save(expiry: Date?, in defaults: UserDefaults) {
        defaults.set(expiry, forKey: expiryKey)
    }

    // ponytail: a renewal is only seen when the app runs, so Pro can look off in the widget
    // until then; have the widget ask StoreKit itself if that shows up in practice.
    public static func isActive(in defaults: UserDefaults, now: Date = .now) -> Bool {
        (defaults.object(forKey: expiryKey) as? Date).map { $0 > now } ?? false
    }
}
