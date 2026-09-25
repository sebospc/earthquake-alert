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
        XCTAssertEqual(derive(), .covered(receptors: 2))
        XCTAssertEqual(derive(coverage: ["chaparral": true, "quibdo": false]), .covered(receptors: 1))
    }

    func testReceptorMissingFromStatusDoesNotCount() {
        XCTAssertEqual(derive(coverage: ["chaparral": true]), .covered(receptors: 1))
        XCTAssertEqual(derive(coverage: [:]), .error(.receptorsDown))
    }

    func testNeverGreenWithoutProof() {
        XCTAssertEqual(derive(registration: .pending), .error(.notRegistered))
        XCTAssertEqual(derive(coverage: nil), .error(.serviceUnreachable))
        XCTAssertEqual(derive(coverage: ["chaparral": false, "quibdo": false]), .error(.receptorsDown))
    }

    func testOutsideCoverage() {
        XCTAssertEqual(derive(registration: .outsideCoverage, coverage: nil), .notCovered)
    }

    func testLiveAlertWinsOverEverything() {
        XCTAssertEqual(derive(coverage: nil, alert: liveAlert), .alert(liveAlert))
    }

    func testExpiredAlertGoesBackToCoverage() {
        let expired = EarthquakeAlert(eventID: "e0", magnitude: 5, late: false, expiresAt: now)
        XCTAssertEqual(derive(alert: expired), .covered(receptors: 2))
    }
}
