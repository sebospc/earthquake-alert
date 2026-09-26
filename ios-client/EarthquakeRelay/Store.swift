import RelayCore
import StoreKit

/// Keeps the Pro expiry in the App Group current. No paywall yet: price and copy wait for the
/// user. Nothing here touches alerts.
enum Store {
    /// At launch, so a purchase finished while the app was closed (or an offer code redeemed in
    /// the App Store) is picked up and finished.
    static func start() {
        Task.detached {
            await refresh()
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await refresh()
            }
        }
    }

    static func refresh() async {
        var purchases: [ProEntitlement.Purchase] = []
        for await entitlement in Transaction.currentEntitlements {
            // An unverified transaction never unlocks anything.
            guard case .verified(let transaction) = entitlement else { continue }
            purchases.append(.init(productID: transaction.productID, expiresAt: transaction.expirationDate,
                                   revokedAt: transaction.revocationDate))
        }
        guard let defaults = AppGroup.defaults else { return }
        ProEntitlement.save(expiry: ProEntitlement.expiry(of: purchases), in: defaults)
    }
}
