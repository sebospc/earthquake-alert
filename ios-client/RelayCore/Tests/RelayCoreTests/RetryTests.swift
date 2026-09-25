import Foundation
import XCTest
@testable import RelayCore

final class RetryTests: XCTestCase {
    func testBackoffDoublesUpToTheCapAndJitterScalesIt() {
        let backoff = Backoff(base: 2, cap: 300)
        XCTAssertEqual((0..<10).map { backoff.delay(attempt: $0, unitRandom: 0.999_999).rounded() },
                       [2, 4, 8, 16, 32, 64, 128, 256, 300, 300])
        XCTAssertEqual(backoff.delay(attempt: 3, unitRandom: 0.5), 8)
        XCTAssertEqual(backoff.delay(attempt: 3, unitRandom: 0), 0)
        XCTAssertEqual(backoff.delay(attempt: 10_000, unitRandom: 0.5), 150, "no overflow on long outages")
    }

    func testRetryableFailuresAreRetriedWithGrowingWaits() async throws {
        let waits = Recorder<TimeInterval>()
        let attempts = Recorder<Int>()

        let value = try await retrying(unitRandom: { 1 }, sleep: { await waits.add($0) }) { () async throws(GatewayClient.Failure) -> String in
            let attempt = await attempts.add(0)
            if attempt < 3 { throw .retryLater }
            return "201"
        }

        XCTAssertEqual(value, "201")
        let recordedWaits = await waits.items
        XCTAssertEqual(recordedWaits, [2, 4, 8])
    }

    func testRejectedIsNeverRetried() async {
        let attempts = Recorder<Int>()
        do {
            _ = try await retrying(sleep: { _ in XCTFail("must not wait") }) { () async throws(GatewayClient.Failure) -> Int in
                await attempts.add(0)
                throw .rejected("invalid sensor_ids")
            }
            XCTFail("expected rejection")
        } catch {
            XCTAssertEqual(error, .rejected("invalid sensor_ids"))
        }
        let count = await attempts.items.count
        XCTAssertEqual(count, 1)
    }

    func testCancellationStopsTheLoop() async {
        // Untyped Task on purpose: a typed-throws Task closure crashes the Swift 6.4 compiler (IRGen).
        let task = Task {
            try await retrying(unitRandom: { 0 }) { () async throws(GatewayClient.Failure) -> Int in throw .retryLater }
        }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
    }

    func testRetriesAgainstTheFakeGatewayUntilItAccepts() async throws {
        nonisolated(unsafe) var calls = 0
        FakeGateway.respond = { _, _ in
            calls += 1
            return calls < 3 ? (429, #"{"error":"too many subscriptions"}"#) : (201, #"{"sensor_ids":["quibdo"]}"#)
        }
        let client = GatewayClient(baseURL: URL(string: "https://gateway.test")!, apnsEnvironment: .sandbox,
                                   session: FakeGateway.session)

        let registered = try await retrying(sleep: { _ in }) { () async throws(GatewayClient.Failure) in
            try await client.subscribe(deviceToken: Data(count: 32), to: .receptors(["quibdo"]))
        }

        XCTAssertEqual(registered.sensorIDs, ["quibdo"])
        XCTAssertEqual(calls, 3)
    }
}

/// Collects values from @Sendable closures; `add` returns the index it was stored at.
private actor Recorder<Item> {
    var items: [Item] = []
    @discardableResult func add(_ item: Item) -> Int {
        items.append(item)
        return items.count - 1
    }
}
