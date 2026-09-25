import Foundation

/// Shared container between the app and the Notification Service Extension.
public enum AppGroup {
    /// From Info.plist, where project.yml derives it from APP_BUNDLE_ID, so changing the bundle id
    /// can't leave the app and the extension writing to different containers.
    public static let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String

    public static var pushArrivalsFile: URL? {
        identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appending(path: "push-arrivals.jsonl")
    }
}
