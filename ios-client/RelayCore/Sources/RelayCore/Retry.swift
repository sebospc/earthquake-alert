import Foundation

/// Capped exponential backoff with full jitter: attempt n waits a random time in
/// [0, min(cap, base * 2^n)]. Jitter keeps many phones from retrying in step after a gateway restart.
public struct Backoff: Sendable {
    public var base: TimeInterval = 2
    public var cap: TimeInterval = 5 * 60

    public init(base: TimeInterval = 2, cap: TimeInterval = 5 * 60) {
        self.base = base
        self.cap = cap
    }

    /// - Parameter unitRandom: a value in [0, 1).
    public func delay(attempt: Int, unitRandom: Double) -> TimeInterval {
        let ceiling = min(cap, base * pow(2, Double(min(attempt, 30))))
        return ceiling * unitRandom
    }
}

extension GatewayClient.Failure {
    public var isRetryable: Bool { self == .retryLater }
}

/// Runs `operation` until it succeeds or fails with `.rejected` (a 4xx never gets better by retrying).
/// Retries `.retryLater` without limit: the screen shows "not registered" meanwhile, and giving up
/// silently would be worse. Stops with `.retryLater` when the task is cancelled.
public func retrying<Value>(
    backoff: Backoff = Backoff(),
    unitRandom: @Sendable () -> Double = { Double.random(in: 0..<1) },
    sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
    _ operation: () async throws(GatewayClient.Failure) -> Value
) async throws(GatewayClient.Failure) -> Value {
    var attempt = 0
    while true {
        do {
            return try await operation()
        } catch where error.isRetryable {
            do {
                try await sleep(backoff.delay(attempt: attempt, unitRandom: unitRandom()))
            } catch {
                throw .retryLater
            }
            if Task.isCancelled { throw .retryLater }
            attempt += 1
        }
    }
}
