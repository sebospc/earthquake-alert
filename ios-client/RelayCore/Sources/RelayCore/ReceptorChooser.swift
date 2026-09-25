import Foundation

/// How well a set of receptors stands in for the user's own phone, in the model of
/// docs/research/ios-techniques.md §4: AEA alerts a device when the epicenter is within R(M) of it,
/// epicenters uniform.
public struct SetQuality: Equatable, Sendable {
    /// Share of the alerts the user's own phone would get that no receptor in the set gets
    /// (weighted over M4.5, M5.0, M5.5).
    public let missShare: Double
    /// Same, at M5.0 only. Decides the coverage tier.
    public let missShareAtM5: Double
    /// Same, at M5.5 only. Decides whether a receptor beyond `enterKm` is still worth following.
    public let missShareAtM55: Double
    /// Share of the alerts the set delivers that the user's own phone would not get, weighted over
    /// the magnitudes the set delivers at all.
    public let falseAlertShare: Double
}

public enum CoverageTier: Equatable, Sendable {
    case full, partial, limited

    init(missShareAtM5: Double) {
        switch missShareAtM5 {
        case ...0.10: self = .full
        case ...0.40: self = .partial
        default: self = .limited
        }
    }
}

public enum ReceptorDecision: Equatable, Sendable {
    /// Keep the current subscription: the set is fine, or the data is too poor to act on.
    case keep
    case subscribe([String])
    case noCoverage(demandCell: String)
}

public struct ReceptorChooser: Sendable {
    /// Magnitude, alert radius R in km (Allen et al. 2025, findings.md §5), weight.
    static let magnitudes: [(magnitude: Double, radiusKm: Double, weight: Double)] = [
        (4.5, 31, 0.2), (5.0, 78, 0.5), (5.5, 197, 0.3),
    ]

    /// Fixed sunflower spiral on the unit disc: evenly spread sample epicenters, deterministic.
    static let discPoints: [SIMD2<Double>] = {
        let count = 256
        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let radius = ((Double(index) + 0.5) / Double(count)).squareRoot()
            let angle = Double(index) * goldenAngle
            return SIMD2(radius * cos(angle), radius * sin(angle))
        }
    }()

    // All [U] until measured on real moves, see the research.
    public var enterKm = 78.0
    public static let strongOnlyMagnitude = 5.5
    public var maxReceptors = 3
    /// Hysteresis: switch only when the new set is better by this much.
    public var switchMargin = 0.03
    /// A missed alert weighs as much as 4 false ones. Without it, a far receptor that adds
    /// a sliver of real coverage and mostly false alerts would always be added.
    public var falseAlertCost = 0.25
    /// A receptor beyond `enterKm` still gets the dangerous quakes to the user (R = 197 km at M5.5).
    /// It is eligible while it alone misses at most this share at M5.5; the tier then reads "limited".
    public var farEnterMissAtM55 = 0.40
    /// Hysteresis for far receptors, like the leave band for near ones.
    public var farStayMissAtM55 = 0.45
    public var maxFixAge: TimeInterval = 30 * 60
    public var maxAccuracyKm = 25.0

    public init() {}

    /// - Parameter covered: `covered_apns` per receptor, nil when /status is unknown. A receptor
    ///   known to be down counts as absent, so it is backfilled instead of kept.
    public func choose(fix: Fix, now: Date, current: [String], sensors: [Sensor], covered: [String: Bool]?) -> ReceptorDecision {
        // Missing or poor data means keep, never drop.
        guard now.timeIntervalSince(fix.timestamp) <= maxFixAge, fix.accuracyKm <= maxAccuracyKm else { return .keep }

        let candidates = sensors.filter { sensor in
            guard sensor.public else { return false }
            if isNear(sensor, fix: fix, current: current) { return true }
            let farLimit = current.contains(sensor.id) ? farStayMissAtM55 : farEnterMissAtM55
            return Self.quality(of: [sensor], from: fix).missShareAtM55 <= farLimit
        }
        let strongOnly = Set(candidates.filter { !isNear($0, fix: fix, current: current) }.map(\.id))
        guard !candidates.isEmpty else { return .noCoverage(demandCell: fix.demandCell) }

        let up = candidates.filter { covered?[$0.id] != false }
        // All down: choose on geometry, so the set is right when they come back.
        let live = up.isEmpty ? candidates : up

        let best = Self.subsets(of: live, upTo: maxReceptors)
            .map { (set: $0, cost: cost(of: $0, from: fix, strongOnly: strongOnly), totalKm: $0.reduce(0) { $0 + Geo.km(fix.lat, fix.lon, $1.lat, $1.lon) }) }
            .min { ($0.cost, $0.totalKm) < ($1.cost, $1.totalKm) }!

        let currentLive = live.filter { current.contains($0.id) }
        if !current.isEmpty, currentLive.count == current.count,
           cost(of: currentLive, from: fix, strongOnly: strongOnly) - best.cost < switchMargin {
            return .keep
        }
        let bestIDs = best.set.map(\.id)
        return Set(bestIDs) == Set(current) ? .keep : .subscribe(bestIDs)
    }

    /// Receptors followed only for strong quakes (`min_magnitude` 5.5 once the contract has it):
    /// the ones admitted by the far rule, not by distance.
    public func strongOnlyIDs(_ ids: [String], fix: Fix, current: [String], sensors: [Sensor]) -> Set<String> {
        Set(sensors.filter { ids.contains($0.id) && !isNear($0, fix: fix, current: current) }.map(\.id))
    }

    private func isNear(_ sensor: Sensor, fix: Fix, current: [String]) -> Bool {
        let distance = Geo.km(fix.lat, fix.lon, sensor.lat, sensor.lon)
        let leaveKm = enterKm + max(10, 2 * fix.accuracyKm)
        return distance <= enterKm || (current.contains(sensor.id) && distance <= leaveKm)
    }

    public func cost(of set: [Sensor], from fix: Fix, strongOnly: Set<String> = []) -> Double {
        let quality = Self.quality(of: set, from: fix, strongOnly: strongOnly)
        return quality.missShare + falseAlertCost * quality.falseAlertShare
    }

    /// - Parameter strongOnly: receptors that only alert from `strongOnlyMagnitude` up.
    public static func quality(of set: [Sensor], from fix: Fix, strongOnly: Set<String> = []) -> SetQuality {
        var missShare = 0.0, missShareAtM5 = 0.0, missShareAtM55 = 0.0
        var weightedFalse = 0.0, deliveringWeight = 0.0

        for (magnitude, radius, weight) in magnitudes {
            let receptors = set.filter { magnitude >= strongOnlyMagnitude || !strongOnly.contains($0.id) }
                .map { Geo.offsetKm(of: $0, from: fix) }
            let reaches = { (epicenter: SIMD2<Double>, receptorsSoFar: ArraySlice<SIMD2<Double>>) in
                receptorsSoFar.contains { distance($0, epicenter) <= radius }
            }
            // Missed: epicenters around the user that no receptor would feel.
            let missed = discPoints.count { !reaches($0 * radius, receptors[...]) }
            let miss = receptors.isEmpty ? 1 : Double(missed) / Double(discPoints.count)

            // False: epicenters in the union of receptor discs but outside the user's disc.
            // Each union point is counted once, by the first receptor whose disc holds it.
            var delivered = 0, falseAlerts = 0
            for (index, receptor) in receptors.enumerated() {
                for point in discPoints {
                    let epicenter = receptor + point * radius
                    if reaches(epicenter, receptors[..<index]) { continue }
                    delivered += 1
                    if distance(epicenter, .zero) > radius { falseAlerts += 1 }
                }
            }
            missShare += weight * miss
            if delivered > 0 {
                weightedFalse += weight * Double(falseAlerts) / Double(delivered)
                deliveringWeight += weight
            }
            if magnitude == 5.0 { missShareAtM5 = miss }
            if magnitude == 5.5 { missShareAtM55 = miss }
        }
        return SetQuality(missShare: missShare, missShareAtM5: missShareAtM5, missShareAtM55: missShareAtM55,
                          falseAlertShare: deliveringWeight == 0 ? 0 : weightedFalse / deliveringWeight)
    }

    public static func tier(of set: [Sensor], from fix: Fix, strongOnly: Set<String> = []) -> CoverageTier {
        CoverageTier(missShareAtM5: quality(of: set, from: fix, strongOnly: strongOnly).missShareAtM5)
    }

    static func subsets(of sensors: [Sensor], upTo maxSize: Int) -> [[Sensor]] {
        var result: [[Sensor]] = [[]]
        for sensor in sensors {
            result += result.filter { $0.count < maxSize }.map { $0 + [sensor] }
        }
        return result.filter { !$0.isEmpty }
    }

    private static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        ((a - b) * (a - b)).sum().squareRoot()
    }
}
