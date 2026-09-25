import Foundation

/// One push as the Notification Service Extension or the app saw it. `sentAtMs` is the gateway
/// clock, `receivedAtMs` the phone clock: compare medians over many pushes, phone clocks drift ~1 s.
public struct PushArrival: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case nse, app }
    public enum AppState: String, Codable, Sendable { case foreground, background, unknown }

    public let kind: String?
    public let eventID: String?
    public let sentAtMs: Int64?
    public let receivedAtMs: Int64
    /// Optional: lines written before these fields existed still decode.
    public let source: Source?
    public let appState: AppState?

    public init(userInfo: [AnyHashable: Any], receivedAt: Date, source: Source = .nse, appState: AppState = .unknown) {
        kind = userInfo["kind"] as? String
        eventID = userInfo["event_id"] as? String
        sentAtMs = (userInfo["sent_at_ms"] as? NSNumber)?.int64Value
        receivedAtMs = Int64((receivedAt.timeIntervalSince1970 * 1000).rounded())
        self.source = source
        self.appState = appState
    }

    /// APNs leg in ms, nil when the gateway did not stamp the push.
    public var latencyMs: Int64? { sentAtMs.map { receivedAtMs - $0 } }
}

/// JSON-lines file in the app group, written by the NSE, read by the app.
public enum PushArrivalLog {
    /// ponytail: keeps the last 500 by rewriting the file; fine at a few pushes a day.
    public static let maxEntries = 500

    public static func append(_ arrival: PushArrival, to file: URL) {
        var lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        guard let line = try? String(decoding: JSONEncoder().encode(arrival), as: UTF8.self) else { return }
        lines.append(line)
        try? lines.suffix(maxEntries).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    public static func read(from file: URL) -> [PushArrival] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(PushArrival.self, from: Data($0.utf8)) }
    }
}
