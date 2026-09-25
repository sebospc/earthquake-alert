import Foundation

/// One sync = choose receptors from the latest fix, then POST /devices through TokenLifecycle.
/// Called on every launch, foreground and location wake: the 201 is the health check.
public actor SubscriptionEngine {
    private struct Stored: Codable {
        /// Last subscription the server confirmed with a 201.
        var subscription: GatewayClient.Subscription?
        var lastFix: Fix?
        /// Last good sensors.json, so a failed download never looks like "no receptors".
        var sensors: [Sensor] = []
    }

    private static let storageKey = "subscription-engine"
    private let lifecycle: TokenLifecycle
    private let chooser: ReceptorChooser
    private let defaults: UserDefaults
    private var stored: Stored

    public init(lifecycle: TokenLifecycle, chooser: ReceptorChooser = ReceptorChooser(), defaults: UserDefaults = .standard) {
        self.lifecycle = lifecycle
        self.chooser = chooser
        self.defaults = defaults
        stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    /// - Parameters:
    ///   - fix: newest location, nil when there is none (denied, not yet).
    ///   - sensors: fresh sensors.json, or nil to use the last good one.
    /// - Returns: `.pending` when there is nothing to register yet (no set and no usable fix).
    public func sync(token: Data, fix: Fix?, sensors freshSensors: [Sensor]?, coverage: [String: Bool]?, now: Date)
        async throws(GatewayClient.Failure) -> Registration {
        if let freshSensors, !freshSensors.isEmpty { stored.sensors = freshSensors }
        if let fix { stored.lastFix = fix }

        var subscription = stored.subscription
        // No sensors known at all: choosing would say "no receptors near you", which is false.
        if let fix, !stored.sensors.isEmpty {
            switch chooser.choose(fix: fix, now: now, current: currentIDs, sensors: stored.sensors, covered: coverage) {
            case .keep: break
            case .subscribe(let ids): subscription = request(for: ids, fix: fix)
            case .noCoverage(let cell): subscription = .demandCell(cell)
            }
        }
        save()
        guard let subscription else { return .pending }

        let registration = try await lifecycle.register(token: token, to: subscription)
        stored.subscription = subscription
        save()
        return registration
    }

    /// Consent withdrawn: forget the confirmed set and the last fix. The public sensors list stays.
    public func forget() {
        stored.subscription = nil
        stored.lastFix = nil
        save()
    }

    /// Tier of the receptors that are up, from the last fix. `.limited` without a fix: never overpromise.
    public func tier(ofUp upIDs: [String]) -> CoverageTier {
        guard let fix = stored.lastFix else { return .limited }
        let set = stored.sensors.filter { upIDs.contains($0.id) }
        let strongOnly = chooser.strongOnlyIDs(upIDs, fix: fix, current: currentIDs, sensors: stored.sensors)
        return ReceptorChooser.tier(of: set, from: fix, strongOnly: strongOnly)
    }

    /// Name and id of the receptors followed now, for the coverage screen.
    public var followedSensors: [Sensor] { stored.sensors.filter { currentIDs.contains($0.id) } }
    public var lastFix: Fix? { stored.lastFix }

    private var currentIDs: [String] {
        stored.subscription?.sensorIDs ?? []
    }

    /// Far receptors get `min_magnitude` 5.5; a "limited" set also sends the cell as demand.
    private func request(for ids: [String], fix: Fix) -> GatewayClient.Subscription {
        let strongOnly = chooser.strongOnlyIDs(ids, fix: fix, current: currentIDs, sensors: stored.sensors)
        let set = stored.sensors.filter { ids.contains($0.id) }
        let limited = ReceptorChooser.tier(of: set, from: fix, strongOnly: strongOnly) == .limited
        return GatewayClient.Subscription(
            sensorIDs: ids,
            minMagnitude: Dictionary(uniqueKeysWithValues: strongOnly.map { ($0, ReceptorChooser.strongOnlyMagnitude) }),
            demandCell: limited ? fix.demandCell : nil)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.storageKey)
    }
}
