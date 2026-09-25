import Foundation
import UserNotifications
import XCTest
@testable import RelayCore

final class PushArrivalTests: XCTestCase {
    func testReadsTheGatewayStampAndComputesTheLeg() {
        let arrival = PushArrival(
            userInfo: ["kind": "alert", "event_id": "chaparral:t1:alert", "sent_at_ms": 1_790_194_180_000],
            receivedAt: Date(timeIntervalSince1970: 1_790_194_180.412))
        XCTAssertEqual(arrival.latencyMs, 412)
        XCTAssertEqual(arrival.kind, "alert")
    }

    func testPushWithoutStampStillLogsArrival() {
        let arrival = PushArrival(userInfo: ["kind": "coverage"], receivedAt: Date(timeIntervalSince1970: 1))
        XCTAssertNil(arrival.latencyMs)
        XCTAssertEqual(arrival.receivedAtMs, 1000)
    }

    func testLogAppendsAndKeepsOnlyTheNewest() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "arrivals-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }

        for index in 0..<(PushArrivalLog.maxEntries + 3) {
            PushArrivalLog.append(PushArrival(userInfo: ["event_id": "e\(index)"], receivedAt: .now), to: file)
        }
        let arrivals = PushArrivalLog.read(from: file)
        XCTAssertEqual(arrivals.count, PushArrivalLog.maxEntries)
        XCTAssertEqual(arrivals.last?.eventID, "e\(PushArrivalLog.maxEntries + 2)")
        XCTAssertEqual(arrivals.first?.eventID, "e3")
    }

    func testPermissionOptionsAndProvisionalCountsAsOff() {
        XCTAssertFalse(NotificationPermission.options(criticalAlertsEntitled: false).contains(.criticalAlert))
        XCTAssertTrue(NotificationPermission.options(criticalAlertsEntitled: true).contains(.criticalAlert))
        XCTAssertFalse(NotificationPermission.options(criticalAlertsEntitled: true).contains(.provisional))
        XCTAssertEqual(NotificationPermission.permission(.provisional), .denied)
        XCTAssertEqual(NotificationPermission.permission(.authorized), .granted)
    }
}
