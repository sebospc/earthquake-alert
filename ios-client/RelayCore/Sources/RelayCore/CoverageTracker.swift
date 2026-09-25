import Foundation

/// Rides out a gateway restart: a /status answer stays valid for `grace` (contract: a restart
/// shorter than 5 min is not an alarm). Past that, or before any answer, coverage is unknown
/// (nil), which the screen shows as red. It never keeps an old green forever.
public struct CoverageTracker: Sendable {
    public static let grace: TimeInterval = 5 * 60

    private var lastAnswer: GatewayClient.ReceptorCoverage?
    private var lastAnswerAt: Date?

    public init() {}

    public mutating func record(_ answer: GatewayClient.ReceptorCoverage, at now: Date) {
        lastAnswer = answer
        lastAnswerAt = now
    }

    public func coverage(at now: Date) -> GatewayClient.ReceptorCoverage? {
        guard let lastAnswerAt, now.timeIntervalSince(lastAnswerAt) < Self.grace else { return nil }
        return lastAnswer
    }
}
