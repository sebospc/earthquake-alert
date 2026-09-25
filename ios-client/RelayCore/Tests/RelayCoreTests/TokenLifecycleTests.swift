import Foundation
import XCTest
@testable import RelayCore

final class TokenLifecycleTests: XCTestCase {
    let oldToken = Data(repeating: 0x01, count: 32)
    let newToken = Data(repeating: 0x02, count: 32)
    let suite = "token-lifecycle-\(UUID())"
    let server = FakeRegistrar()

    override func setUp() { Consent.give(in: UserDefaults(suiteName: suite)!) }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testNothingIsSentBeforeConsent() async {
        UserDefaults().removePersistentDomain(forName: suite)
        do {
            _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
            XCTFail("registered without consent")
        } catch {
            XCTAssertEqual(error, .rejected("consent not given"))
        }
        let calls = await server.calls
        XCTAssertEqual(calls, [])
    }

    func testWithdrawnConsentBlocksTheNextRegistration() async throws {
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        Consent.withdraw(in: UserDefaults(suiteName: suite)!)
        do {
            _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
            XCTFail("registered after withdrawal")
        } catch {
            XCTAssertEqual(error, .rejected("consent not given"))
        }
    }

    func testUnregisterDeletesAndForgetsTheToken() async {
        _ = try? await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        let confirmed = await lifecycle().unregister()
        XCTAssertTrue(confirmed)
        let calls = await server.calls
        XCTAssertEqual(calls.last, .delete(oldToken))
        let pending = await lifecycle().hasPendingDeletes
        XCTAssertFalse(pending)
    }

    func testFailedUnregisterSaysSoAndKeepsTheDeleteForLater() async {
        _ = try? await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        await server.failDeletes(true)
        let confirmed = await lifecycle().unregister()
        XCTAssertFalse(confirmed, "the user must be told the server was not reached")
        let pending = await lifecycle().hasPendingDeletes
        XCTAssertTrue(pending)

        await server.failDeletes(false)
        await lifecycle().retryPendingDeletes()
        let stillPending = await lifecycle().hasPendingDeletes
        XCTAssertFalse(stillPending)
    }

    func testTelemetryFlagFollowsTheLast201AndA404TurnsItOff() async throws {
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        var enabled = await lifecycle().telemetryEnabled
        XCTAssertFalse(enabled, "absent in the 201 means off")

        await server.optInToTelemetry(true)
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        enabled = await lifecycle().telemetryEnabled
        XCTAssertTrue(enabled)

        await lifecycle().telemetryTurnedOff()
        enabled = await lifecycle().telemetryEnabled
        XCTAssertFalse(enabled)

        await lifecycle().unregister()
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        enabled = await lifecycle().telemetryEnabled
        XCTAssertTrue(enabled, "the next 201 turns it back on")
    }

    func testAnOlderConsentVersionIsNotEnough() {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Consent.current - 1, forKey: "consent-version")
        XCTAssertFalse(Consent.isGiven(in: defaults))
    }

    /// A fresh instance on the same storage, like an app relaunch.
    private func lifecycle(deviceID: String = "phone-A") -> TokenLifecycle {
        TokenLifecycle(registrar: server, defaults: UserDefaults(suiteName: suite)!, deviceID: deviceID)
    }

    func testRegisterPostsAndReturnsWhatTheServerConfirmed() async throws {
        let registration = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))

        XCTAssertEqual(registration, .receptors(["chaparral"]))
        let calls = await server.calls
        XCTAssertEqual(calls, [.post(oldToken, .receptors(["chaparral"]))])
    }

    func testDemandCellRegistrationMeansOutsideCoverage() async throws {
        let registration = try await lifecycle().register(token: oldToken, to: .demandCell("37,-755"))
        XCTAssertEqual(registration, .outsideCoverage)
    }

    func testSameTokenPostsAgainAndDeletesNothing() async throws {
        let phone = lifecycle()
        _ = try await phone.register(token: oldToken, to: .receptors(["chaparral"]))
        _ = try await phone.register(token: oldToken, to: .receptors(["chaparral"]))

        let calls = await server.calls
        XCTAssertEqual(calls.count, 2, "the server may have lost us: every sync is proven by a fresh 201")
        XCTAssertFalse(calls.contains { if case .delete = $0 { true } else { false } })
    }

    func testNewTokenOnTheSamePhoneDeletesTheOldOneFirst() async throws {
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        // App relaunched (new instance, same storage) with a new token.
        _ = try await lifecycle().register(token: newToken, to: .receptors(["quibdo"]))

        let calls = await server.calls
        XCTAssertEqual(calls.suffix(2), [.delete(oldToken), .post(newToken, .receptors(["quibdo"]))])
    }

    func testRestoreOnANewPhoneLeavesTheOldPhonesTokenAlone() async throws {
        _ = try await lifecycle(deviceID: "phone-A").register(token: oldToken, to: .receptors(["chaparral"]))
        _ = try await lifecycle(deviceID: "phone-B").register(token: newToken, to: .receptors(["chaparral"]))

        let calls = await server.calls
        XCTAssertFalse(calls.contains(.delete(oldToken)), "phone A may still be in use")
    }

    func testFailedDeleteDoesNotBlockTheNewTokenAndIsRetriedLater() async throws {
        _ = try await lifecycle().register(token: oldToken, to: .receptors(["chaparral"]))
        await server.failDeletes(true)

        let phone = lifecycle()
        let registration = try await phone.register(token: newToken, to: .receptors(["chaparral"]))
        XCTAssertEqual(registration, .receptors(["chaparral"]))
        let stillPending = await phone.pendingDeletes
        XCTAssertEqual(stillPending, [oldToken])

        await server.failDeletes(false)
        _ = try await lifecycle().register(token: newToken, to: .receptors(["chaparral"]))
        let afterRetry = await lifecycle().pendingDeletes
        XCTAssertEqual(afterRetry, [])
        let deletes = await server.calls.filter { $0 == .delete(oldToken) }
        XCTAssertEqual(deletes.count, 2)
    }

    func testUnregisterThenReEnableWithTheSameTokenNeverDeletesTheLiveToken() async throws {
        let phone = lifecycle()
        _ = try await phone.register(token: oldToken, to: .receptors(["chaparral"]))
        await server.failDeletes(true)
        await phone.unregister()   // DELETE fails, stays pending
        await server.failDeletes(false)

        _ = try await phone.register(token: oldToken, to: .receptors(["chaparral"]))

        let calls = await server.calls
        XCTAssertEqual(calls.last, .post(oldToken, .receptors(["chaparral"])))
        XCTAssertEqual(calls.filter { $0 == .delete(oldToken) }.count, 1, "only the failed one from unregister")
        let pending = await phone.pendingDeletes
        XCTAssertEqual(pending, [])
    }

    func testRejectedPostThrowsSoTheScreenStaysNotRegistered() async {
        await server.rejectPosts("invalid sensor_ids")
        do {
            _ = try await lifecycle().register(token: oldToken, to: .receptors(["glan"]))
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error, .rejected("invalid sensor_ids"))
        }
    }
}

actor FakeRegistrar: DeviceRegistrar {
    enum Call: Equatable {
        case post(Data, GatewayClient.Subscription)
        case delete(Data)
    }

    private(set) var calls: [Call] = []
    private var deletesFail = false
    private var postRejection: String?
    private var telemetry = false

    func failDeletes(_ fail: Bool) { deletesFail = fail }
    func optInToTelemetry(_ on: Bool) { telemetry = on }
    func rejectPosts(_ message: String) { postRejection = message }

    func subscribe(deviceToken: Data, to subscription: GatewayClient.Subscription) async throws(GatewayClient.Failure) -> GatewayClient.Registered {
        calls.append(.post(deviceToken, subscription))
        if let postRejection { throw .rejected(postRejection) }
        return .init(sensorIDs: subscription.sensorIDs, demandCell: subscription.demandCell, telemetry: telemetry)
    }

    func unsubscribe(deviceToken: Data) async throws(GatewayClient.Failure) {
        calls.append(.delete(deviceToken))
        if deletesFail { throw .retryLater }
    }
}
