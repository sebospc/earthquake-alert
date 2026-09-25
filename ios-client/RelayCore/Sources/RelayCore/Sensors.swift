import Foundation

/// GET /sensors.json. Only `public` sensors may be subscribed to.
public struct SensorsFile: Decodable, Sendable {
    public struct Coverage: Decodable, Sendable {
        public let fullKm: Double
        public let partialKm: Double
        enum CodingKeys: String, CodingKey { case fullKm = "full_km", partialKm = "partial_km" }
    }
    public let coverage: Coverage
    public let sensors: [Sensor]
}

public struct Sensor: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let `public`: Bool

    public init(id: String, name: String = "", lat: Double, lon: Double, public isPublic: Bool = true) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.public = isPublic
    }
}

/// A location reading. Stays on the phone.
public struct Fix: Codable, Sendable, Equatable {
    public let lat: Double
    public let lon: Double
    public let accuracyKm: Double
    public let timestamp: Date

    public init(lat: Double, lon: Double, accuracyKm: Double, timestamp: Date) {
        self.lat = lat
        self.lon = lon
        self.accuracyKm = accuracyKm
        self.timestamp = timestamp
    }

    /// The contract's ~11 km cell, the only location data that ever leaves the phone.
    public var demandCell: String { "\(Int((lat * 10).rounded(.down))),\(Int((lon * 10).rounded(.down)))" }
}

enum Geo {
    static let earthRadiusKm = 6371.0

    /// Haversine, as gateway/public/coverage.js.
    static func km(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = pow(sin(dLat / 2), 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * pow(sin(dLon / 2), 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
    }

    /// Position of a sensor in km on a flat plane centred on the fix (x east, y north).
    /// Good enough within a few hundred km, which is all the model needs.
    static func offsetKm(of sensor: Sensor, from fix: Fix) -> SIMD2<Double> {
        let kmPerDegree = earthRadiusKm * .pi / 180
        return SIMD2((sensor.lon - fix.lon) * kmPerDegree * cos(fix.lat * .pi / 180), (sensor.lat - fix.lat) * kmPerDegree)
    }
}
