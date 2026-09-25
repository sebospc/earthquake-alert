import CoreLocation
import RelayCore

/// Significant-location-change only (docs/research/ios-techniques.md §3). Never relied on after a
/// force-quit: the subscription lives on the server, a missed wake only leaves the set stale.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onFix: (Fix) -> Void = { _ in }
    var onDenied: (Bool) -> Void = { _ in }

    private let manager = CLLocationManager()
    /// iOS 18+: background use only holds while a session is alive. Recreated on every launch.
    private var session: CLServiceSession?
    private static let askedAlwaysKey = "asked-location-always"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            session = CLServiceSession(authorization: .always)
            manager.startMonitoringSignificantLocationChanges()
        case .authorizedWhenInUse:
            session = CLServiceSession(authorization: .whenInUse)
            manager.startMonitoringSignificantLocationChanges()
        default:
            break
        }
        onDenied(manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted)
    }

    /// First run, right after the notification permission.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// After the first armed state, once: iOS then offers "Always" with our purpose string.
    func requestAlwaysOnce() {
        guard manager.authorizationStatus == .authorizedWhenInUse,
              !UserDefaults.standard.bool(forKey: Self.askedAlwaysKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    /// On app open, one fresh reading instead of trusting an old one.
    func requestFreshFix() {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse { manager.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        let fix = Fix(lat: newest.coordinate.latitude, lon: newest.coordinate.longitude,
                      accuracyKm: newest.horizontalAccuracy / 1000, timestamp: newest.timestamp)
        MainActor.assumeIsolated { onFix(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed reading changes nothing: the chooser keeps the current set without a fresh fix.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            start()
            requestFreshFix()
        }
    }
}
