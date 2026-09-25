import Foundation
import UserNotifications
import XCTest
@testable import RelayCore

final class SubscriptionEngineTests: XCTestCase {
    let suite = "engine-\(UUID())"
    let server = FakeRegistrar()
    let token = Data(repeating: 0x07, count: 32)
    let now = Date(timeIntervalSince1970: 1_790_194_200)
    let chaparral = Sensor(id: "chaparral", lat: 3.7236, lon: -75.4836)
    let quibdo = Sensor(id: "quibdo", lat: 5.6947, lon: -76.6611)

    override func setUp() { Consent.give(in: UserDefaults(suiteName: suite)!) }

    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }

    /// Fresh instance on the same storage, like an app relaunch.
    private func engine() -> SubscriptionEngine {
        SubscriptionEngine(lifecycle: TokenLifecycle(registrar: server, defaults: UserDefaults(suiteName: suite)!, deviceID: "phone"),
                           defaults: UserDefaults(suiteName: suite)!)
    }

    private func fix(_ lat: Double, _ lon: Double, ageS: TimeInterval = 0) -> Fix {
        Fix(lat: lat, lon: lon, accuracyKm: 1, timestamp: now - ageS)
    }

    func testFirstSyncChoosesAndRegisters() async throws {
        let registration = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral, quibdo], coverage: nil, now: now)
        XCTAssertEqual(registration, .receptors(["chaparral"]))
    }

    func testNoFixAndNoSetIsPendingWithoutCallingTheServer() async throws {
        let registration = try await engine().sync(token: token, fix: nil, sensors: [chaparral], coverage: nil, now: now)
        XCTAssertEqual(registration, .pending)
        let calls = await server.calls
        XCTAssertEqual(calls, [])
    }

    func testLaterWakeWithoutFixStillRePostsTheConfirmedSet() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        let registration = try await engine().sync(token: token, fix: nil, sensors: nil, coverage: nil, now: now + 3600)
        XCTAssertEqual(registration, .receptors(["chaparral"]))
        let posts = await server.calls.count
        XCTAssertEqual(posts, 2, "every wake is a health check")
    }

    func testStaleFixKeepsTheSet() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral, quibdo], coverage: nil, now: now)
        // Old reading from Quibdó: not trusted, set stays.
        let registration = try await engine().sync(token: token, fix: fix(5.69, -76.66, ageS: 3600), sensors: nil, coverage: nil, now: now)
        XCTAssertEqual(registration, .receptors(["chaparral"]))
    }

    func testForgetDropsTheConfirmedSetAndTheFix() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        await engine().forget()
        let followed = await engine().followedSensors
        let lastFix = await engine().lastFix
        XCTAssertEqual(followed, [])
        XCTAssertNil(lastFix)
    }

    func testFailedSensorsDownloadNeverMeansNoCoverage() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        // sensors.json failed (nil) and never known in a fresh install either: no demand cell.
        let fresh = SubscriptionEngine(lifecycle: TokenLifecycle(registrar: server, defaults: UserDefaults(suiteName: "\(suite)-2")!, deviceID: "p"),
                                       defaults: UserDefaults(suiteName: "\(suite)-2")!)
        defer { UserDefaults().removePersistentDomain(forName: "\(suite)-2") }
        let registration = try await fresh.sync(token: token, fix: fix(3.72, -75.48), sensors: nil, coverage: nil, now: now)
        XCTAssertEqual(registration, .pending)
        let last = await server.calls.last
        XCTAssertEqual(last, .post(token, .receptors(["chaparral"])), "the fresh install did not POST a demand cell")
    }

    func testMovingOutOfRangeSendsTheDemandCell() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        let registration = try await engine().sync(token: token, fix: fix(6.2442, -75.5812), sensors: nil, coverage: nil, now: now)
        XCTAssertEqual(registration, .outsideCoverage)
        let last = await server.calls.last
        XCTAssertEqual(last, .post(token, .demandCell("62,-756")))
    }

    func testRejectedPostKeepsTheLastConfirmedSet() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral, quibdo], coverage: nil, now: now)
        await server.rejectPosts("invalid sensor_ids")
        do {
            _ = try await engine().sync(token: token, fix: fix(5.69, -76.66), sensors: nil, coverage: nil, now: now)
            XCTFail("expected rejection")
        } catch {}
        let followed = await engine().followedSensors.map(\.id)
        XCTAssertEqual(followed, ["chaparral"], "only a 201 changes what we believe the server holds")
    }

    func testFarReceptorGoesStrongOnlyAndLimitedSendsTheCell() async throws {
        // Ibagué, 84 km from Chaparral: far rule.
        let registration = try await engine().sync(token: token, fix: fix(4.4389, -75.2322), sensors: [chaparral, quibdo], coverage: nil, now: now)
        XCTAssertEqual(registration, .receptors(["chaparral"]))
        let last = await server.calls.last
        XCTAssertEqual(last, .post(token, .init(sensorIDs: ["chaparral"], minMagnitude: ["chaparral": 5.5], demandCell: "44,-753")))
    }

    func testNearFullSetSendsNoFilterAndNoCell() async throws {
        _ = try await engine().sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        let last = await server.calls.last
        XCTAssertEqual(last, .post(token, .receptors(["chaparral"])))
    }

    func testTierUsesTheLastFix() async throws {
        let phone = engine()
        _ = try await phone.sync(token: token, fix: fix(3.72, -75.48), sensors: [chaparral], coverage: nil, now: now)
        let tier = await phone.tier(ofUp: ["chaparral"])
        XCTAssertEqual(tier, .full)
    }

    func testDeadManReminderReplacesItselfAndFiresAfterEightDays() throws {
        let request = DeadManReminder.request()
        XCTAssertEqual(request.identifier, DeadManReminder.identifier)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 8 * 24 * 3600)
        XCTAssertFalse(trigger.repeats)
    }
}
