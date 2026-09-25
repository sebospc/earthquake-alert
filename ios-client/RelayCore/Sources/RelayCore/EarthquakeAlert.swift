import Foundation

/// An alert push (`kind: "alert"`), on time or late. See docs/ios-contract.md, "Alert".
public struct EarthquakeAlert: Equatable, Sendable, Decodable {
    public let eventID: String
    public let magnitude: Double?
    public let late: Bool
    public let expiresAt: Date
    /// The gateway's words: `aps.alert.body`, or what iOS and the NSE showed for its loc-key
    /// (see `PushText`). The app shows these and adds no advice of its own.
    public var body: String?
    /// "Probar alerta" push (`kind: "test"`): same screen, no magnitude, nothing a real alert does beyond the sound.
    public let isTest: Bool

    public init(eventID: String, magnitude: Double?, late: Bool, expiresAt: Date, body: String? = nil, isTest: Bool = false) {
        self.eventID = eventID
        self.magnitude = magnitude
        self.late = late
        self.expiresAt = expiresAt
        self.body = body
        self.isTest = isTest
    }

    /// nil for coverage pushes and malformed payloads.
    public init?(userInfo: [AnyHashable: Any]) {
        if userInfo["kind"] as? String == "test" {
            // Same 60 s life as the push's apns-expiration.
            let sentAtMs = (userInfo["sent_at_ms"] as? NSNumber)?.int64Value
            let sentAt = sentAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
            let body = ((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any])?["body"] as? String
            self.init(eventID: "test:\(sentAtMs ?? 0)", magnitude: nil, late: false, expiresAt: sentAt + 60, body: body, isTest: true)
            return
        }
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

    /// "M4.8" in English, "M4,8" in Colombian Spanish: the phone's decimal separator.
    public var magnitudeText: String? { magnitudeText(locale: .current) }

    public func magnitudeText(locale: Locale) -> String? {
        magnitude.map { "M" + $0.formatted(.number.precision(.fractionLength(1)).locale(locale)) }
    }

    /// After `expires_at` the notice no longer helps anyone take cover.
    public func isActive(at now: Date) -> Bool { now < expiresAt }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", magnitude, late, expiresAt = "expires_at", aps
    }

    private struct APS: Decodable {
        struct Alert: Decodable { let body: String? }
        let alert: Alert?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(String.self, forKey: .eventID)
        magnitude = try container.decodeIfPresent(Double.self, forKey: .magnitude)
        late = try container.decode(Bool.self, forKey: .late)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        body = (try? container.decodeIfPresent(APS.self, forKey: .aps))?.alert?.body
        isTest = false
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
