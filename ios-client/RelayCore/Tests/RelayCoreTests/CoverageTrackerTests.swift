import Foundation
import XCTest
@testable import RelayCore

final class CoverageTrackerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_194_200)

    func testUnknownBeforeTheFirstAnswer() {
        XCTAssertNil(CoverageTracker().coverage(at: start))
    }

    func testLastAnswerHoldsThroughAShortRestartThenGoesUnknown() {
        var tracker = CoverageTracker()
        tracker.record(["chaparral": true], at: start)

        XCTAssertEqual(tracker.coverage(at: start + CoverageTracker.grace - 1), ["chaparral": true])
        XCTAssertNil(tracker.coverage(at: start + CoverageTracker.grace), "never an old green forever")
    }

    func testANewAnswerRestartsTheGraceAndReplacesTheOldOne() {
        var tracker = CoverageTracker()
        tracker.record(["chaparral": true], at: start)
        tracker.record(["chaparral": false], at: start + 200)

        XCTAssertEqual(tracker.coverage(at: start + 400), ["chaparral": false])
    }

    /// The grace is for /status not answering. An answer that says "down" shows at once.
    func testAnAnswerSayingDownIsShownImmediately() {
        var tracker = CoverageTracker()
        tracker.record(["chaparral": true], at: start)
        tracker.record(["chaparral": false], at: start + 10)

        XCTAssertEqual(tracker.coverage(at: start + 10), ["chaparral": false])
        XCTAssertEqual(
            AppState.derive(permission: .granted, registration: .receptors(["chaparral"]),
                            receptorCoverage: tracker.coverage(at: start + 10), alert: nil, now: start + 10),
            .error(.receptorsDown))
    }
}
