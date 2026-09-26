import Foundation
import XCTest
@testable import RelayCore

final class ProEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ProEntitlementTests")
        defaults.removePersistentDomain(forName: "ProEntitlementTests")
    }

    func testLatestExpiryOfTheProPurchasesWins() {
        let expiry = ProEntitlement.expiry(of: [
            .init(productID: "pro.monthly", expiresAt: now.addingTimeInterval(86_400), revokedAt: nil),
            .init(productID: "pro.yearly", expiresAt: now.addingTimeInterval(86_400 * 300), revokedAt: nil),
        ])
        XCTAssertEqual(expiry, now.addingTimeInterval(86_400 * 300))
    }

    func testRefundedOrOtherProductsGiveNoPro() {
        XCTAssertNil(ProEntitlement.expiry(of: [
            .init(productID: "pro.yearly", expiresAt: now.addingTimeInterval(86_400), revokedAt: now),
            .init(productID: "tip.coffee", expiresAt: now.addingTimeInterval(86_400), revokedAt: nil),
        ]))
        XCTAssertNil(ProEntitlement.expiry(of: []))
    }

    func testStoredExpiryTurnsProOffByTheClock() {
        XCTAssertFalse(ProEntitlement.isActive(in: defaults, now: now), "nothing stored means no Pro")
        ProEntitlement.save(expiry: now.addingTimeInterval(60), in: defaults)
        XCTAssertTrue(ProEntitlement.isActive(in: defaults, now: now))
        XCTAssertFalse(ProEntitlement.isActive(in: defaults, now: now.addingTimeInterval(61)), "lapsed without the app running")
        ProEntitlement.save(expiry: nil, in: defaults)
        XCTAssertFalse(ProEntitlement.isActive(in: defaults, now: now))
    }
}
