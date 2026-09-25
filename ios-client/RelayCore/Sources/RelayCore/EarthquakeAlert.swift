import Foundation

/// An alert push (`kind: "alert"`), on time or late. See docs/ios-contract.md, "Alert".
public struct EarthquakeAlert: Equatable, Sendable, Decodable {
    public let eventID: String
    public let magnitude: Double?
    public let late: Bool
    public let expiresAt: Date

    public init(eventID: String, magnitude: Double?, late: Bool, expiresAt: Date) {
        self.eventID = eventID
        self.magnitude = magnitude
        self.late = late
        self.expiresAt = expiresAt
    }

    /// nil for coverage pushes and malformed payloads.
    public init?(userInfo: [AnyHashable: Any]) {
        guard userInfo["kind"] as? String == "alert" else { return nil }
        let jsonObject = Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            (key as? String).map { ($0, value) }
        })
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject),
              let alert = try? Self.decoder.decode(Self.self, from: data)
        else { return nil }
        self = alert
    }

    /// "M4.8". Always a dot, like the gateway's text, whatever the phone's locale.
    public var magnitudeText: String? {
        magnitude.map { String(format: "M%.1f", $0) }
    }

    /// After `expires_at` the notice no longer helps anyone take cover.
    public func isActive(at now: Date) -> Bool { now < expiresAt }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", magnitude, late, expiresAt = "expires_at"
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            guard let date = (try? withFraction.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
            }
            return date
        }
        return decoder
    }()
}
