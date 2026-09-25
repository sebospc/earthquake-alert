import Foundation
import XCTest
@testable import RelayCore

final class EarthquakeAlertTests: XCTestCase {
    /// The contract's sample alert, as iOS hands it over in `userInfo`.
    let contractAlert: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "Alerta de sismo", "body": "Sismo M4.8 cerca de su zona. Protéjase ahora."]],
        "kind": "alert",
        "event_id": "chaparral:t1790194179:alert",
        "sensor_id": "chaparral",
        "magnitude": 4.45852,
        "distance_km": 40.2,
        "time_occurred_s": 1790194179,
        "late": false,
        "expires_at": "2026-09-24T10:05:00.000Z",
    ]

    func testDecodesTheContractSample() throws {
        let alert = try XCTUnwrap(EarthquakeAlert(userInfo: contractAlert))
        XCTAssertEqual(alert.eventID, "chaparral:t1790194179:alert")
        XCTAssertEqual(alert.magnitudeText(locale: Locale(identifier: "en_US")), "M4.5")
        XCTAssertFalse(alert.late)
        XCTAssertEqual(alert.body, "Sismo M4.8 cerca de su zona. Protéjase ahora.")
        XCTAssertEqual(alert.expiresAt, ISO8601DateFormatter().date(from: "2026-09-24T10:05:00Z"))
    }

    func testNullMagnitudeAndDateWithoutFraction() throws {
        var payload = contractAlert
        payload["magnitude"] = NSNull()
        payload["expires_at"] = "2026-09-24T10:05:00Z"
        let alert = try XCTUnwrap(EarthquakeAlert(userInfo: payload))
        XCTAssertNil(alert.magnitudeText)
    }

    func testCoveragePushIsNotAnAlert() {
        XCTAssertNil(EarthquakeAlert(userInfo: ["kind": "coverage", "sensor_id": NSNull(), "covered": false]))
    }

    func testMagnitudeUsesThePhonesDecimalSeparator() {
        let alert = EarthquakeAlert(eventID: "e", magnitude: 4.8, late: false, expiresAt: .now)
        XCTAssertEqual(alert.magnitudeText(locale: Locale(identifier: "en_US")), "M4.8")
        XCTAssertEqual(alert.magnitudeText(locale: Locale(identifier: "es_CO")), "M4,8")
        XCTAssertEqual(alert.magnitudeText(locale: Locale(identifier: "pt_BR")), "M4,8")
        XCTAssertEqual(alert.magnitudeText(locale: Locale(identifier: "en_US")),
                       EarthquakeAlert(eventID: "e", magnitude: 4.75, late: false, expiresAt: .now)
                           .magnitudeText(locale: Locale(identifier: "en_US")), "one decimal, rounded")
    }
}
