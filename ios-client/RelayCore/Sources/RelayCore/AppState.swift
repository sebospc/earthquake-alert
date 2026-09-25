import Foundation

/// What the one screen shows.
public enum AppState: Equatable, Sendable {
    case notSetUp
    case askingPermission
    case covered(receptors: Int)
    case notCovered
    case alert(EarthquakeAlert)
    case error(Problem)

    public enum Problem: Equatable, Sendable {
        case notificationsOff
        case notRegistered
        case serviceUnreachable
        case receptorsDown
    }
}

public enum Permission: Sendable {
    case notDetermined, requesting, denied, granted
}

public enum Registration: Equatable, Sendable {
    /// No 201 from POST /devices yet, or the last attempt failed.
    case pending
    case receptors([String])
    case outsideCoverage
}

extension AppState {
    /// The only place that decides the screen. Anything unknown or broken ends in `.error`,
    /// never in a green state: a silent failure is worse than a loud one.
    /// - Parameter receptorCoverage: `covered_apns` per receptor from GET /status, nil when it did not answer.
    public static func derive(
        permission: Permission,
        registration: Registration,
        receptorCoverage: [String: Bool]?,
        alert: EarthquakeAlert?,
        now: Date
    ) -> AppState {
        if let alert, alert.isActive(at: now) { return .alert(alert) }

        switch permission {
        case .notDetermined: return .notSetUp
        case .requesting: return .askingPermission
        case .denied: return .error(.notificationsOff)
        case .granted: break
        }

        switch registration {
        case .pending:
            return .error(.notRegistered)
        case .outsideCoverage:
            return .notCovered
        case .receptors(let sensorIDs):
            // ponytail: /status down = red at once. Contract allows a 5 min grace for gateway restarts; add it with the refresh loop.
            guard let receptorCoverage else { return .error(.serviceUnreachable) }
            let coveringCount = sensorIDs.filter { receptorCoverage[$0] == true }.count
            return coveringCount == 0 ? .error(.receptorsDown) : .covered(receptors: coveringCount)
        }
    }
}
