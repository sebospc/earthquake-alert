import Foundation

/// State of the "Probar alerta" row: sent, waiting for the push, arrived or not, and the
/// 10-min wait between tests (the gateway enforces it too; this keeps the button honest).
public struct TestAlertTracker: Sendable {
    public enum Status: Equatable, Sendable {
        case ready, sending, waiting, arrived, notArrived, tooSoon, notRegistered, paused, failed
    }

    public static let arrivalTimeout: TimeInterval = 30
    public static let cooldown: TimeInterval = 10 * 60

    private var outcome = Status.ready
    private(set) var lastSentAt: Date?

    public init() {}

    public mutating func started() { outcome = .sending }

    public mutating func accepted(at now: Date) {
        outcome = .waiting
        lastSentAt = now
    }

    public mutating func failed(_ failure: GatewayClient.TestAlertFailure) {
        switch failure {
        case .tooSoon: outcome = .tooSoon
        case .notRegistered: outcome = .notRegistered
        case .relayPaused: outcome = .paused
        case .rejected, .unreachable: outcome = .failed
        }
    }

    /// A test push reached the phone. Late (after the 30 s notice) still counts: it did arrive.
    public mutating func pushArrived() {
        if outcome == .waiting || outcome == .notArrived { outcome = .arrived }
    }

    /// Arrivals the NSE logged while the app was not in front.
    public mutating func check(_ arrivals: [PushArrival]) {
        guard let lastSentAt else { return }
        // The push can land before the 202 gets back to the app: allow a few seconds before it.
        let earliestMs = Int64((lastSentAt.timeIntervalSince1970 - 5) * 1000)
        if arrivals.contains(where: { $0.kind == "test" && $0.receivedAtMs >= earliestMs }) { pushArrived() }
    }

    public func status(at now: Date) -> Status {
        if outcome == .waiting, let lastSentAt, now.timeIntervalSince(lastSentAt) >= Self.arrivalTimeout { return .notArrived }
        return outcome
    }

    public func canSend(at now: Date) -> Bool {
        let status = status(at: now)
        if status == .sending || status == .waiting { return false }
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= Self.cooldown
    }
}
