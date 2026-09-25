import Foundation
import XCTest
@testable import RelayCore

final class AppStateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_194_200)
    lazy var liveAlert = EarthquakeAlert(eventID: "e1", magnitude: 4.8, late: false, expiresAt: now + 60)

    private func derive(
        permission: Permission = .granted,
        registration: Registration = .receptors(["chaparral", "quibdo"]),
        coverage: [String: Bool]? = ["chaparral": true, "quibdo": true],
        alert: EarthquakeAlert? = nil
    ) -> AppState {
        AppState.derive(permission: permission, registration: registration, receptorCoverage: coverage, alert: alert, now: now)
    }

    func testSetupStates() {
        XCTAssertEqual(derive(permission: .notDetermined), .notSetUp)
        XCTAssertEqual(derive(permission: .requesting), .askingPermission)
        XCTAssertEqual(derive(permission: .denied), .error(.notificationsOff))
    }

    func testCoveredCountsOnlyReceptorsThatAreUp() {
        XCTAssertEqual(derive(), .covered(.full))
        XCTAssertEqual(derive(coverage: ["chaparral": true, "quibdo": false]), .covered(.full))
    }

    func testReceptorMissingFromStatusDoesNotCount() {
        XCTAssertEqual(derive(coverage: ["chaparral": true]), .covered(.full))
        XCTAssertEqual(derive(coverage: [:]), .error(.receptorsDown))
    }

    func testNeverGreenWithoutProof() {
        XCTAssertEqual(derive(registration: .pending), .error(.notRegistered))
        XCTAssertEqual(derive(coverage: nil), .error(.serviceUnreachable))
        XCTAssertEqual(derive(coverage: ["chaparral": false, "quibdo": false]), .error(.receptorsDown))
    }

    func testTierComesFromTheReceptorsThatAreUp() {
        let state = AppState.derive(permission: .granted, registration: .receptors(["chaparral", "quibdo"]),
                                    receptorCoverage: ["chaparral": true, "quibdo": false],
                                    tier: { $0 == ["chaparral"] ? .limited : .full }, alert: nil, now: now)
        XCTAssertEqual(state, .covered(.limited))
    }

    func testTimeSensitiveOffIsAWarningOnlyWhenOtherwiseCovered() {
        XCTAssertEqual(AppState.derive(permission: .granted, timeSensitiveOn: false, registration: .receptors(["chaparral"]),
                                       receptorCoverage: ["chaparral": true], alert: nil, now: now), .error(.timeSensitiveOff))
        XCTAssertEqual(AppState.derive(permission: .granted, timeSensitiveOn: false, registration: .receptors(["chaparral"]),
                                       receptorCoverage: ["chaparral": false], alert: nil, now: now), .error(.receptorsDown),
                       "the worse problem wins")
    }

    func testNoSetAndNoLocationAsksForLocation() {
        XCTAssertEqual(AppState.derive(permission: .granted, locationDenied: true, registration: .pending,
                                       receptorCoverage: nil, alert: nil, now: now), .error(.locationOff))
    }

    func testOutsideCoverage() {
        XCTAssertEqual(derive(registration: .outsideCoverage, coverage: nil), .notCovered)
    }

    func testLiveAlertWinsOverEverything() {
        XCTAssertEqual(derive(coverage: nil, alert: liveAlert), .alert(liveAlert))
    }

    func testExpiredAlertGoesBackToCoverage() {
        let expired = EarthquakeAlert(eventID: "e0", magnitude: 5, late: false, expiresAt: now)
        XCTAssertEqual(derive(alert: expired), .covered(.full))
    }
}
