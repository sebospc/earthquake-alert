import Foundation

/// Uploads the arrival log of an opted-in test phone (docs/ios-contract.md, "Arrival telemetry").
/// Never on the alert path: it only reads the log file the extension already wrote.
public actor ArrivalUploader {
    public static let batchSize = 500
    /// The server takes only these; anything else (coverage pushes) stays local.
    static let uploadedKinds: Set<String> = ["alert", "test", "probe"]
    private static let watermarkKey = "arrival-upload-watermark"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `receivedAtMs` of the newest arrival the server has taken or refused for good.
    public var watermark: Int64 { Int64(defaults.integer(forKey: Self.watermarkKey)) }

    /// Oldest first, newer than the watermark, at most one batch.
    public func nextBatch(from arrivals: [PushArrival]) -> [PushArrival] {
        let pending = arrivals.filter { arrival in
            arrival.receivedAtMs > watermark && arrival.sentAtMs != nil && arrival.eventID != nil
                && arrival.kind.map(Self.uploadedKinds.contains) == true
        }
        return Array(pending.sorted { $0.receivedAtMs < $1.receivedAtMs }.prefix(Self.batchSize))
    }

    /// Sends batches until nothing is left. Returns `.telemetryOff` when the server said so.
    /// Throws `.retryLater` with the watermark kept, so the next call resends the same batch
    /// (the server dedups on event_id and source).
    public func upload(_ arrivals: [PushArrival],
                       send: @Sendable ([PushArrival]) async throws(GatewayClient.Failure) -> GatewayClient.TelemetryUpload)
        async throws(GatewayClient.Failure) -> GatewayClient.TelemetryUpload {
        while case let batch = nextBatch(from: arrivals), let newest = batch.last {
            switch try await send(batch) {
            case .telemetryOff: return .telemetryOff
            case .stored, .invalid: defaults.set(Int(newest.receivedAtMs), forKey: Self.watermarkKey)
            }
        }
        return .stored
    }
}
