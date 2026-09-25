import Foundation
import XCTest
@testable import RelayCore

final class ReceptorChooserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_194_200)
    let chooser = ReceptorChooser()
    let home = (lat: 4.4389, lon: -75.2322) // Ibagué

    private func fix(eastKm: Double = 0, northKm: Double = 0, accuracyKm: Double = 1, ageS: TimeInterval = 0) -> Fix {
        let point = place(eastKm: eastKm, northKm: northKm)
        return Fix(lat: point.lat, lon: point.lon, accuracyKm: accuracyKm, timestamp: now - ageS)
    }

    private func sensor(_ id: String, km: Double, bearing: Double, public isPublic: Bool = true) -> Sensor {
        let radians = bearing * .pi / 180
        let point = place(eastKm: km * sin(radians), northKm: km * cos(radians))
        return Sensor(id: id, lat: point.lat, lon: point.lon, public: isPublic)
    }

    private func place(eastKm: Double, northKm: Double) -> (lat: Double, lon: Double) {
        let kmPerDegree = Geo.earthRadiusKm * .pi / 180
        return (home.lat + northKm / kmPerDegree, home.lon + eastKm / (kmPerDegree * cos(home.lat * .pi / 180)))
    }

    // MARK: the model matches the research tables (§4)

    func testQualityMatchesTheResearchTables() {
        let one = ReceptorChooser.quality(of: [sensor("a", km: 31, bearing: 0)], from: fix())
        XCTAssertEqual(one.missShareAtM5, 0.25, accuracy: 0.02)
        let opposite = ReceptorChooser.quality(of: [sensor("a", km: 31, bearing: 0), sensor("b", km: 31, bearing: 180)], from: fix())
        XCTAssertEqual(opposite.missShareAtM5, 0.01, accuracy: 0.01)
        let triangle = ReceptorChooser.quality(
            of: [sensor("a", km: 31, bearing: 0), sensor("b", km: 31, bearing: 120), sensor("c", km: 31, bearing: 240)], from: fix())
        XCTAssertEqual(triangle.missShare, 0, accuracy: 0.01)
        XCTAssertEqual(one.falseAlertShare, 0.28, accuracy: 0.03)
    }

    func testTiers() {
        XCTAssertEqual(ReceptorChooser.tier(of: [sensor("a", km: 5, bearing: 0)], from: fix()), .full)
        XCTAssertEqual(ReceptorChooser.tier(of: [sensor("a", km: 31, bearing: 0)], from: fix()), .partial)
        XCTAssertEqual(ReceptorChooser.tier(of: [sensor("a", km: 60, bearing: 0)], from: fix()), .limited)
    }

    // MARK: choice

    func testSurroundingBeatsNearest() {
        let sensors = [sensor("n1", km: 20, bearing: 0), sensor("n2", km: 22, bearing: 10), sensor("n3", km: 24, bearing: 350),
                       sensor("south", km: 30, bearing: 180)]
        guard case .subscribe(let chosen) = chooser.choose(fix: fix(), now: now, current: [], sensors: sensors, covered: nil) else {
            return XCTFail("expected a subscription")
        }
        XCTAssertTrue(chosen.contains("south"), "the one on the other side matters more than a third on the same side: \(chosen)")
    }

    func testFarReceptorThatMostlyAddsFalseAlertsIsLeftOut() {
        let sensors = [sensor("near", km: 10, bearing: 0), sensor("far", km: 70, bearing: 180)]
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: [], sensors: sensors, covered: nil), .subscribe(["near"]))
    }

    func testNoPublicReceptorInRangeSendsTheDemandCell() {
        let sensors = [sensor("far", km: 140, bearing: 0), sensor("canary", km: 5, bearing: 0, public: false)]
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: [], sensors: sensors, covered: nil),
                       .noCoverage(demandCell: "44,-753"))
    }

    func testPoorOrOldFixKeepsTheCurrentSet() {
        let sensors = [sensor("a", km: 10, bearing: 0)]
        XCTAssertEqual(chooser.choose(fix: fix(accuracyKm: 30), now: now, current: ["x"], sensors: sensors, covered: nil), .keep)
        XCTAssertEqual(chooser.choose(fix: fix(ageS: 31 * 60), now: now, current: ["x"], sensors: sensors, covered: nil), .keep)
    }

    func testDownReceptorIsBackfilled() {
        let sensors = [sensor("a", km: 10, bearing: 0), sensor("b", km: 15, bearing: 180)]
        let decision = chooser.choose(fix: fix(), now: now, current: ["a", "b"], sensors: sensors, covered: ["a": false, "b": true])
        XCTAssertEqual(decision, .subscribe(["b"]))
    }

    func testAllDownKeepsTheGeometricSetInsteadOfDroppingCoverage() {
        let sensors = [sensor("a", km: 10, bearing: 0)]
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: ["a"], sensors: sensors, covered: ["a": false]), .keep)
    }

    func testFarReceptorStillDeliversTheDangerousQuakesAsLimited() {
        let far = sensor("far", km: 100, bearing: 0)
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: [], sensors: [far], covered: nil), .subscribe(["far"]))
        XCTAssertEqual(ReceptorChooser.tier(of: [far], from: fix()), .limited)
    }

    func testStrongOnlyReceptorCountsOnlyForStrongQuakes() {
        let far = sensor("far", km: 120, bearing: 0)
        let all = ReceptorChooser.quality(of: [far], from: fix())
        let strong = ReceptorChooser.quality(of: [far], from: fix(), strongOnly: ["far"])
        XCTAssertEqual(strong.missShareAtM5, 1, "no M5.0 alert from a strong-only receptor")
        XCTAssertEqual(strong.missShareAtM55, all.missShareAtM55)
        XCTAssertLessThan(strong.falseAlertShare, all.falseAlertShare - 0.2)
        XCTAssertEqual(chooser.strongOnlyIDs(["far"], fix: fix(), current: [], sensors: [far]), ["far"])
        XCTAssertEqual(chooser.strongOnlyIDs(["near"], fix: fix(), current: [], sensors: [sensor("near", km: 20, bearing: 0)]), [])
    }

    func testFarReceptorHasItsOwnStayBand() {
        // Between the enter (40%) and stay (45%) M5.5 miss share: kept if followed, not taken if new.
        let edge = sensor("edge", km: 132, bearing: 0)
        let miss = ReceptorChooser.quality(of: [edge], from: fix()).missShareAtM55
        XCTAssert(miss > 0.40 && miss <= 0.45, "fixture moved: \(miss)")
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: ["edge"], sensors: [edge], covered: nil), .keep)
        XCTAssertEqual(chooser.choose(fix: fix(), now: now, current: [], sensors: [edge], covered: nil),
                       .noCoverage(demandCell: fix().demandCell))
    }

    /// Walking from one receptor to the other in 1 km steps: west, then both (they surround the
    /// user in the middle), then east. Never back to an earlier set, and jittering ±1 km around
    /// each switch point never switches again.
    func testWalkBetweenTwoReceptorsNeverFlipFlops() {
        let sensors = [sensor("west", km: 80, bearing: 270), sensor("east", km: 80, bearing: 90)]
        var current: [String] = []
        var seen: [Set<String>] = []
        var switchPoints: [(km: Double, set: [String])] = []
        for step in stride(from: -65.0, through: 65, by: 1) {
            if case .subscribe(let chosen) = chooser.choose(fix: fix(eastKm: step), now: now, current: current, sensors: sensors, covered: nil) {
                XCTAssertFalse(seen.contains(Set(chosen)), "went back to \(chosen) at \(step) km")
                seen.append(Set(chosen))
                current = chosen
                switchPoints.append((step, chosen))
            }
        }
        XCTAssertEqual(seen, [["west"], ["west", "east"], ["east"]])

        for (km, set) in switchPoints.dropFirst() {
            for jitter in [-1.0, 0, 1, 0, -1] {
                XCTAssertEqual(chooser.choose(fix: fix(eastKm: km + jitter), now: now, current: set, sensors: sensors, covered: nil),
                               .keep, "flip at \(km + jitter) km")
            }
        }
    }

    func testSubsetsUpToThree() {
        let five = (0..<5).map { sensor("s\($0)", km: 10, bearing: Double($0) * 72) }
        XCTAssertEqual(ReceptorChooser.subsets(of: five, upTo: 3).count, 5 + 10 + 10)
    }
}
