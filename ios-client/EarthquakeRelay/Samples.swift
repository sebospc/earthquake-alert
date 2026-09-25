#if DEBUG
import Foundation
import RelayCore

/// One of each state, for previews and `-state <name>` screenshots.
extension AppState {
    static let sampleAlert = EarthquakeAlert(eventID: "e1", magnitude: 4.8, late: false, expiresAt: .distantFuture,
                                             body: "Sismo M4.8 cerca de su zona. Protéjase ahora.")
    static let sampleLateAlert = EarthquakeAlert(eventID: "e2", magnitude: 5.2, late: true, expiresAt: .distantFuture,
                                                 body: "El sismo ocurrió hace 3 min. Ya no es un aviso anticipado.")

    static let sampleTestAlert = EarthquakeAlert(eventID: "test:1", magnitude: nil, late: false, expiresAt: .distantFuture,
                                                 body: "Así sonará una alerta de sismo. Esto es solo una prueba.", isTest: true)

    static let samples: [(name: String, state: AppState)] = [
        ("not-set-up", .notSetUp),
        ("asking-permission", .askingPermission),
        ("covered-full", .covered(.full)),
        ("covered-partial", .covered(.partial)),
        ("covered-limited", .covered(.limited)),
        ("not-covered", .notCovered),
        ("alert", .alert(sampleAlert)),
        ("late-alert", .alert(sampleLateAlert)),
        ("test-alert", .alert(sampleTestAlert)),
        ("notifications-off", .error(.notificationsOff)),
        ("time-sensitive-off", .error(.timeSensitiveOff)),
        ("location-off", .error(.locationOff)),
        ("not-registered", .error(.notRegistered)),
        ("unreachable", .error(.serviceUnreachable)),
        ("receptors-down", .error(.receptorsDown)),
    ]
}
#endif
