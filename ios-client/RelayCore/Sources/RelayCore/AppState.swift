import Foundation

/// What the one screen shows.
public enum AppState: Equatable, Sendable {
    case notSetUp
    case askingPermission
    case covered(CoverageTier)
    case notCovered
    case alert(EarthquakeAlert)
    case error(Problem)

    public enum Problem: Equatable, Sendable {
        case notificationsOff
        /// Alerts arrive, but Focus may silence them.
        case timeSensitiveOff
        /// No receptor set yet and no location to choose one.
        case locationOff
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
    /// - Parameters:
    ///   - receptorCoverage: from `CoverageTracker`: nil when /status has not answered within the grace.
    ///   - tier: coverage tier of the receptors that are up.
    public static func derive(
        permission: Permission,
        timeSensitiveOn: Bool = true,
        locationDenied: Bool = false,
        registration: Registration,
        receptorCoverage: [String: Bool]?,
        tier: ([String]) -> CoverageTier = { _ in .full },
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
            return .error(locationDenied ? .locationOff : .notRegistered)
        case .outsideCoverage:
            return .notCovered
        case .receptors(let sensorIDs):
            guard let receptorCoverage else { return .error(.serviceUnreachable) }
            let upIDs = sensorIDs.filter { receptorCoverage[$0] == true }
            if upIDs.isEmpty { return .error(.receptorsDown) }
            if !timeSensitiveOn { return .error(.timeSensitiveOff) }
            return .covered(tier(upIDs))
        }
    }
}
