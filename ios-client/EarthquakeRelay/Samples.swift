#if DEBUG
import Foundation
import RelayCore

/// One of each state, for previews and `-state <name>` screenshots.
extension AppState {
    static let samples: [(name: String, state: AppState)] = [
        ("not-set-up", .notSetUp),
        ("asking-permission", .askingPermission),
        ("covered", .covered(receptors: 2)),
        ("not-covered", .notCovered),
        ("alert", .alert(EarthquakeAlert(eventID: "e1", magnitude: 4.8, late: false, expiresAt: .distantFuture))),
        ("late-alert", .alert(EarthquakeAlert(eventID: "e2", magnitude: 5.2, late: true, expiresAt: .distantFuture))),
        ("notifications-off", .error(.notificationsOff)),
        ("not-registered", .error(.notRegistered)),
        ("unreachable", .error(.serviceUnreachable)),
        ("receptors-down", .error(.receptorsDown)),
    ]

    static func sample(_ name: String) -> AppState {
        samples.first { $0.name == name }!.state
    }
}
#endif
