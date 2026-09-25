import Foundation
import XCTest
@testable import RelayCore

final class TestAlertTrackerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_194_200)

    private func sentTracker() -> TestAlertTracker {
        var tracker = TestAlertTracker()
        tracker.started()
        tracker.accepted(at: now)
        return tracker
    }

    func testWaitingTurnsIntoNotArrivedAfter30Seconds() {
        let tracker = sentTracker()
        XCTAssertEqual(tracker.status(at: now + 29), .waiting)
        XCTAssertEqual(tracker.status(at: now + 30), .notArrived)
    }

    func testArrivalInAppOrLateStillCounts() {
        var tracker = sentTracker()
        tracker.pushArrived()
        XCTAssertEqual(tracker.status(at: now + 100), .arrived)

        var late = sentTracker()
        _ = late.status(at: now + 40)
        late.pushArrived()
        XCTAssertEqual(late.status(at: now + 45), .arrived)
    }

    func testArrivalFromTheExtensionLog() {
        var tracker = sentTracker()
        tracker.check([PushArrival(userInfo: ["kind": "alert"], receivedAt: now + 2)])
        XCTAssertEqual(tracker.status(at: now + 3), .waiting, "a real alert is not the test")
        tracker.check([PushArrival(userInfo: ["kind": "test"], receivedAt: now - 60)])
        XCTAssertEqual(tracker.status(at: now + 3), .waiting, "an old test does not count")
        tracker.check([PushArrival(userInfo: ["kind": "test"], receivedAt: now - 1)])
        XCTAssertEqual(tracker.status(at: now + 3), .arrived, "the push can beat the 202")
    }

    func testTenMinutesBetweenTests() {
        var tracker = TestAlertTracker()
        XCTAssertTrue(tracker.canSend(at: now))
        tracker.started()
        XCTAssertFalse(tracker.canSend(at: now), "no double tap while sending")
        tracker.accepted(at: now)
        tracker.pushArrived()
        XCTAssertFalse(tracker.canSend(at: now + 599))
        XCTAssertTrue(tracker.canSend(at: now + 600))
    }

    func testFailuresMapToWhatTheRowSays() {
        let cases: [(GatewayClient.TestAlertFailure, TestAlertTracker.Status)] = [
            (.tooSoon, .tooSoon), (.notRegistered, .notRegistered), (.relayPaused, .paused),
            (.unreachable, .failed), (.rejected("x"), .failed)]
        for (failure, expected) in cases {
            var tracker = TestAlertTracker()
            tracker.started()
            tracker.failed(failure)
            XCTAssertEqual(tracker.status(at: now), expected)
            XCTAssertTrue(tracker.canSend(at: now), "a failed attempt does not start the 10 min wait")
        }
    }

    func testTestPushOpensTheAlertScreenAsATest() throws {
        let alert = try XCTUnwrap(EarthquakeAlert(userInfo: [
            "aps": ["alert": ["title": "Alerta de prueba", "body": "Así sonará una alerta de sismo. Esto es solo una prueba."]],
            "kind": "test", "sent_at_ms": 1_790_194_180_512]))
        XCTAssertTrue(alert.isTest)
        XCTAssertNil(alert.magnitudeText)
        XCTAssertFalse(alert.late)
        XCTAssertEqual(alert.body, "Así sonará una alerta de sismo. Esto es solo una prueba.")
        XCTAssertEqual(alert.expiresAt, Date(timeIntervalSince1970: 1_790_194_240.512))
    }
}

final class GatewayTestAlertTests: XCTestCase {
    let client = GatewayClient(baseURL: URL(string: "https://gateway.test")!, apnsEnvironment: .sandbox, session: FakeGateway.session)
    let token = Data(repeating: 0xAB, count: 32)

    func testAcceptedReturnsSentAt() async throws {
        FakeGateway.respond = { request, _ in
            XCTAssertEqual(request.url?.path, "/devices/test")
            return (202, #"{"sent_at_ms":1790194180512,"event_id":"test:6f1c"}"#)
        }
        let sentAtMs = try await client.sendTestAlert(deviceToken: token)
        XCTAssertEqual(sentAtMs, 1_790_194_180_512)
        XCTAssertEqual(Array(FakeGateway.lastBody.keys), ["device_token"])
    }

    func testFailureMapping() async {
        let cases: [(Int, String, GatewayClient.TestAlertFailure)] = [
            (404, #"{"error":"unknown device_token"}"#, .notRegistered),
            (429, #"{"error":"one test alert per 10 min"}"#, .tooSoon),
            (429, #"{"error":"too many subscriptions"}"#, .tooSoon),
            (503, #"{"error":"relay paused"}"#, .relayPaused),
            (503, "", .unreachable),
            (400, #"{"error":"invalid device_token"}"#, .rejected("invalid device_token")),
        ]
        for (status, body, expected) in cases {
            FakeGateway.respond = { _, _ in (status, body) }
            do {
                _ = try await client.sendTestAlert(deviceToken: token)
                XCTFail("\(status) must fail")
            } catch {
                XCTAssertEqual(error, expected, "\(status) \(body)")
            }
        }
        FakeGateway.respond = { _, _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client.sendTestAlert(deviceToken: token); XCTFail() } catch { XCTAssertEqual(error, .unreachable) }
    }
}
