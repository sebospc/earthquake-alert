import Foundation

/// What TokenLifecycle needs from the server. GatewayClient is the real one; the push
/// mechanism the research picks only has to hand over a token.
public protocol DeviceRegistrar: Sendable {
    func subscribe(deviceToken: Data, to subscription: GatewayClient.Subscription) async throws(GatewayClient.Failure) -> GatewayClient.Registered
    func unsubscribe(deviceToken: Data) async throws(GatewayClient.Failure)
}

extension GatewayClient: DeviceRegistrar {}

/// Keeps the server's view of this phone right across token changes, updates and restores.
///
/// Every `register` POSTs, even when nothing changed locally: the server can lose a token
/// (BadDeviceToken purge, data loss) and a local "already registered" would then stay green
/// with no proof. That also covers new token, new receptor set and app update without
/// tracking what changed.
public actor TokenLifecycle {
    private struct Stored: Codable {
        var token: Data?
        /// identifierForVendor at the last registration. A backup restored on a new phone
        /// brings the old phone's token along; that token may still be alive on the old
        /// phone, so it is not deleted. A dead one is purged by the server on BadDeviceToken.
        var deviceID: String?
        /// Old tokens whose DELETE has not succeeded yet.
        var pendingDeletes: [Data] = []
        /// From the last 201. Optional so storage written before it existed still decodes.
        var telemetry: Bool?
    }

    private static let storageKey = "token-lifecycle"
    private let registrar: any DeviceRegistrar
    private let defaults: UserDefaults
    private let deviceID: String
    private var stored: Stored
    /// Bumped by every register and unregister. The actor is reentrant across each network call,
    /// so a response only counts if nothing newer started meanwhile.
    private var generation = 0
    /// The DELETE run in progress. Runs are chained, so a POST never overtakes a DELETE of the same token.
    private var deleting: Task<Void, Never>?

    public init(registrar: any DeviceRegistrar, defaults: UserDefaults = .standard, deviceID: String) {
        self.registrar = registrar
        self.defaults = defaults
        self.deviceID = deviceID
        stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    /// Old token cleanup first, then the POST. Only a 201 for `token` returns; anything else
    /// throws, and the screen stays "not registered". Wrap it in `retrying`.
    public func register(token: Data, to subscription: GatewayClient.Subscription) async throws(GatewayClient.Failure) -> Registration {
        // The one place a POST /devices starts, so the consent check lives here and not in the UI.
        guard Consent.isGiven(in: defaults) else { throw .rejected("consent not given") }
        if let oldToken = stored.token, oldToken != token, stored.deviceID == deviceID {
            stored.pendingDeletes.append(oldToken)
        }
        stored.token = token
        stored.deviceID = deviceID
        stored.pendingDeletes.removeAll { $0 == token }
        save()
        generation += 1
        let myGeneration = generation

        // Also waits for a DELETE of this same token still in flight (withdraw, then accept again).
        await retryPendingDeletes()

        let registered = try await registrar.subscribe(deviceToken: token, to: subscription)
        if stored.token == nil {
            // Consent was withdrawn while this POST was in flight: it may have landed after the DELETE.
            stored.pendingDeletes.append(token)
            save()
            await retryPendingDeletes()
            throw .rejected("unregistered meanwhile")
        }
        guard generation == myGeneration else { throw .rejected("superseded by a newer registration") }
        stored.telemetry = registered.telemetry
        save()
        return registered.sensorIDs.isEmpty ? .outsideCoverage : .receptors(registered.sensorIDs)
    }

    /// The user withdrew consent. A failed DELETE is kept and retried by `retryPendingDeletes`.
    /// - Returns: true when the server has confirmed every DELETE.
    @discardableResult
    public func unregister() async -> Bool {
        if let token = stored.token {
            stored.pendingDeletes.append(token)
        }
        stored.token = nil
        stored.telemetry = nil
        save()
        generation += 1
        await retryPendingDeletes()
        return stored.pendingDeletes.isEmpty
    }

    /// The operator opted this phone in: the last 201 said `telemetry: true`.
    public var telemetryEnabled: Bool { stored.telemetry == true }

    /// A 404 from /telemetry/arrivals: stop until a 201 says otherwise.
    public func telemetryTurnedOff() {
        stored.telemetry = false
        save()
    }

    /// Never throws: a stuck old token must not block registering the current one.
    public func retryPendingDeletes() async {
        let previous = deleting
        let run = Task {
            await previous?.value
            await deletePending()
        }
        deleting = run
        await run.value
    }

    private func deletePending() async {
        for oldToken in Set(stored.pendingDeletes) {
            // Registered again while an earlier DELETE ran: this token is live now.
            guard stored.pendingDeletes.contains(oldToken) else { continue }
            if (try? await registrar.unsubscribe(deviceToken: oldToken)) != nil {
                // Only the one that succeeded: tokens added during the await stay pending.
                stored.pendingDeletes.removeAll { $0 == oldToken }
                save()
            }
        }
    }

    public var hasPendingDeletes: Bool { !stored.pendingDeletes.isEmpty }

    var pendingDeletes: [Data] { stored.pendingDeletes }

    private func save() {
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.storageKey)
    }
}
