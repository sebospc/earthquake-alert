import RelayCore
import StoreKitTest
import XCTest
@testable import EarthquakeRelay

/// Runs against StoreKit/Pro.storekit on the simulator; no App Store account involved.
final class StoreTests: XCTestCase {
    func testPurchaseTurnsProOnAndRefundTurnsItOff() async throws {
        let session = try SKTestSession(configurationFileNamed: "Pro")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let defaults = try XCTUnwrap(AppGroup.defaults, "no App Group identifier in the host app's Info.plist")

        await Store.refresh()
        XCTAssertFalse(ProEntitlement.isActive(in: defaults))

        let transaction = try await session.buyProduct(identifier: "pro.yearly")
        let turnedOn = await refreshUntil { ProEntitlement.isActive(in: defaults) }
        XCTAssertTrue(turnedOn, "a purchase must give Pro")

        try session.refundTransaction(identifier: UInt(transaction.id))
        let turnedOff = await refreshUntil { !ProEntitlement.isActive(in: defaults) }
        XCTAssertTrue(turnedOff, "a refund must take Pro away")
    }

    /// The test session applies a purchase or a refund a moment after the call returns; in the
    /// app, Transaction.updates triggers the refresh instead.
    private func refreshUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            await Store.refresh()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        return false
    }
}
