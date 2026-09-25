import Foundation
import XCTest
@testable import RelayCore

final class ArrivalUploaderTests: XCTestCase {
    let suite = "arrival-uploader-\(UUID())"

    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }

    private func uploader() -> ArrivalUploader { ArrivalUploader(defaults: UserDefaults(suiteName: suite)!) }

    private func arrival(_ kind: String?, receivedAtMs: Int64, sentAtMs: Int64? = 1_000, id: String = "e") -> PushArrival {
        var userInfo: [AnyHashable: Any] = ["event_id": "\(id)\(receivedAtMs)"]
        userInfo["kind"] = kind
        userInfo["sent_at_ms"] = sentAtMs.map { NSNumber(value: $0) }
        return PushArrival(userInfo: userInfo, receivedAt: Date(timeIntervalSince1970: Double(receivedAtMs) / 1000))
    }

    func testBatchIsOldestFirstAndOnlyStampedAlertTestAndProbePushes() async {
        let log = [arrival("test", receivedAtMs: 3_000), arrival("alert", receivedAtMs: 2_000),
                   arrival("coverage", receivedAtMs: 2_500), arrival("probe", receivedAtMs: 4_000, sentAtMs: nil),
                   arrival(nil, receivedAtMs: 5_000)]
        let batch = await uploader().nextBatch(from: log)
        XCTAssertEqual(batch.map(\.receivedAtMs), [2_000, 3_000])
    }

    func testStoredBatchIsNeverSentAgain() async throws {
        let log = [arrival("alert", receivedAtMs: 2_000), arrival("test", receivedAtMs: 3_000)]
        let sent = Recorded()
        let result = try await uploader().upload(log) { batch in await sent.add(batch.count); return .stored }
        XCTAssertEqual(result, .stored)
        _ = try await uploader().upload(log) { batch in await sent.add(batch.count); return .stored }
        let counts = await sent.values
        XCTAssertEqual(counts, [2])
    }

    func testMoreThanOneBatchGoesOutInSeveralPosts() async throws {
        let log = (1...ArrivalUploader.batchSize + 20).map { arrival("probe", receivedAtMs: Int64($0)) }
        let sent = Recorded()
        _ = try await uploader().upload(log) { batch in await sent.add(batch.count); return .stored }
        let counts = await sent.values
        XCTAssertEqual(counts, [ArrivalUploader.batchSize, 20])
    }

    func testRefusedBatchIsDroppedNotRetried() async throws {
        let log = [arrival("alert", receivedAtMs: 2_000)]
        _ = try await uploader().upload(log) { _ in .invalid }
        let next = await uploader().nextBatch(from: log)
        XCTAssertEqual(next, [])
    }

    func testTelemetryOffStopsAndKeepsEverything() async throws {
        let log = [arrival("alert", receivedAtMs: 2_000)]
        let result = try await uploader().upload(log) { _ in .telemetryOff }
        XCTAssertEqual(result, .telemetryOff)
        let next = await uploader().nextBatch(from: log)
        XCTAssertEqual(next.count, 1)
    }

    func testRetryLaterKeepsTheBatchForTheNextTry() async {
        let log = [arrival("alert", receivedAtMs: 2_000)]
        do {
            _ = try await uploader().upload(log) { _ throws(GatewayClient.Failure) in throw .retryLater }
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error, .retryLater)
        }
        let next = await uploader().nextBatch(from: log)
        XCTAssertEqual(next.count, 1)
    }
}

private actor Recorded {
    private(set) var values: [Int] = []
    func add(_ value: Int) { values.append(value) }
}
