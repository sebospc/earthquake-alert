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

    // MARK: reentrancy (QA-111, QA-112)

    func testAcceptingAgainWhileTheWithdrawDeleteIsInFlightPostsOnlyAfterIt() async throws {
        let lifecycle = lifecycle()
        _ = try await lifecycle.register(token: oldToken, to: .receptors(["chaparral"]))
        await server.holdDeletes()
        let withdraw = Task { await lifecycle.unregister() }
        await eventually { await self.server.heldDeleteCount == 1 }

        let accept = Task { [token = oldToken] in try await lifecycle.register(token: token, to: .receptors(["chaparral"])) }
        // Gives an early POST every chance to go out; with the DELETE unanswered it must not.
        await eventually { await self.server.calls.count > 2 }
        var calls = await server.calls
        XCTAssertEqual(calls.last, .delete(oldToken), "the POST went out before the DELETE was answered")

        await server.releaseDeletes()
        _ = await withdraw.value
        _ = try await accept.value
        calls = await server.calls
        XCTAssertEqual(Array(calls.suffix(2)), [.delete(oldToken), .post(oldToken, .receptors(["chaparral"]))])
        let pending = await lifecycle.hasPendingDeletes
        XCTAssertFalse(pending, "the live token must not be deleted again")
    }

    func testAnOlderRegisterAnsweringLastDoesNotOverwriteTelemetry() async throws {
        let lifecycle = lifecycle()
        await server.holdPosts()
        await server.optInToTelemetry(true)
        let older = Task { [token = oldToken] in try await lifecycle.register(token: token, to: .receptors(["chaparral"])) }
        await eventually { await self.server.heldPostCount == 1 }
        await server.optInToTelemetry(false)
        let newer = Task { [token = oldToken] in try await lifecycle.register(token: token, to: .receptors(["chaparral"])) }
        await eventually { await self.server.heldPostCount == 2 }

        await server.releasePost(1)
        _ = try await newer.value
        await server.releasePost(0)
        do {
            _ = try await older.value
            XCTFail("the older answer must not count")
        } catch {
            XCTAssertEqual(error as? GatewayClient.Failure, .rejected("superseded by a newer registration"))
        }
        let enabled = await lifecycle.telemetryEnabled
        XCTAssertFalse(enabled, "the newer 201 said off")
    }

    func testARegisterThatLandsAfterWithdrawalIsDeletedAgain() async throws {
        let lifecycle = lifecycle()
        await server.holdPosts()
        let register = Task { [token = oldToken] in try await lifecycle.register(token: token, to: .receptors(["chaparral"])) }
        await eventually { await self.server.heldPostCount == 1 }
        await lifecycle.unregister()

        await server.releasePost(0)
        do {
            _ = try await register.value
            XCTFail("a registration after withdrawal must not count")
        } catch {
            XCTAssertEqual(error as? GatewayClient.Failure, .rejected("unregistered meanwhile"))
        }
        let calls = await server.calls
        XCTAssertEqual(calls.last, .delete(oldToken), "the POST may have landed after the first DELETE")
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
    /// While set, each request waits after being recorded (sent) until released: the answer is in flight.
    private var holdingPosts = false
    private var holdingDeletes = false
    private var heldPosts: [CheckedContinuation<Void, Never>?] = []
    private var heldDeletes: [CheckedContinuation<Void, Never>] = []

    func failDeletes(_ fail: Bool) { deletesFail = fail }
    func optInToTelemetry(_ on: Bool) { telemetry = on }
    func rejectPosts(_ message: String) { postRejection = message }
    func holdPosts() { holdingPosts = true }
    func holdDeletes() { holdingDeletes = true }
    var heldPostCount: Int { heldPosts.count }
    var heldDeleteCount: Int { heldDeletes.count }

    /// Answers the `index`-th held POST (in the order they were sent).
    func releasePost(_ index: Int) {
        heldPosts[index]?.resume()
        heldPosts[index] = nil
    }

    func releaseDeletes() {
        holdingDeletes = false
        heldDeletes.forEach { $0.resume() }
        heldDeletes = []
    }

    func subscribe(deviceToken: Data, to subscription: GatewayClient.Subscription) async throws(GatewayClient.Failure) -> GatewayClient.Registered {
        calls.append(.post(deviceToken, subscription))
        let telemetryWhenSent = telemetry
        if holdingPosts { await withCheckedContinuation { heldPosts.append($0) } }
        if let postRejection { throw .rejected(postRejection) }
        return .init(sensorIDs: subscription.sensorIDs, demandCell: subscription.demandCell, telemetry: telemetryWhenSent)
    }

    func unsubscribe(deviceToken: Data) async throws(GatewayClient.Failure) {
        calls.append(.delete(deviceToken))
        if holdingDeletes { await withCheckedContinuation { heldDeletes.append($0) } }
        if deletesFail { throw .retryLater }
    }
}

/// Waits until `condition` holds, for held requests to be sent.
func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<1000 where !(await condition()) { await Task.yield() }
}
