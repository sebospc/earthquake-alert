import Foundation

/// Ley 1581 art. 9: nothing about the user goes to the server before an explicit "Acepto".
/// Versioned: a new aviso de privacidad raises `current` and asks again.
public enum Consent {
    public static let current = 1
    private static let key = "consent-version"

    public static func isGiven(in defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key) >= current
    }

    public static func give(in defaults: UserDefaults = .standard) {
        defaults.set(current, forKey: key)
    }

    /// "Retirar consentimiento" (Ley 1581 art. 8 e): back to the consent screen.
    public static func withdraw(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
