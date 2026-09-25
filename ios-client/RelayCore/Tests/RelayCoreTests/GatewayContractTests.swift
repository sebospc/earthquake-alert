import CryptoKit
import Foundation
import XCTest
@testable import RelayCore

/// GatewayClient against the real gateway (gateway/src/server.js, APNs dry run) to catch
/// contract drift the fake cannot see. Needs `node` on PATH and `npm install` done in gateway/.
final class GatewayContractTests: XCTestCase {
    static let gatewayDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../gateway").standardized

    var gateway: Process!
    var dataDirectory: URL!
    var client: GatewayClient!
    let token = Data((0..<32).map { UInt8($0) })

    override func setUp() async throws {
        try await startGateway()
    }

    private func startGateway(extraEnvironment: [String: String] = [:]) async throws {
        gateway?.terminate()
        gateway?.waitUntilExit()
        if let oldDirectory = dataDirectory { try? FileManager.default.removeItem(at: oldDirectory) }
        dataDirectory = FileManager.default.temporaryDirectory.appending(path: "gateway-contract-\(UUID())")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let port = Int.random(in: 20_000..<40_000)

        gateway = Process()
        gateway.executableURL = URL(filePath: "/usr/bin/env")
        gateway.arguments = ["node", "src/server.js"]
        gateway.currentDirectoryURL = Self.gatewayDirectory
        gateway.environment = ProcessInfo.processInfo.environment.merging([
            "PORT": "\(port)",
            "APNS_DRY_RUN": "1",
            "RELAY_HMAC_SECRET": "contract-test",
            "APNS_TEAM_ID": "TEAM",
            "APNS_KEY_ID": "KEY",
            "APNS_BUNDLE_ID": "com.example.earthquakerelay",
            "DEVICES_FILE": file("devices.json"),
            "SUBSCRIPTIONS_FILE": file("subscriptions.json"),
            "COVERAGE_STATE_FILE": file("coverage-state.json"),
            "HEARTBEATS_FILE": file("heartbeats.json"),
            "EVIDENCE_FILE": file("evidence.jsonl"),
        ].merging(extraEnvironment) { _, extra in extra }) { _, test in test }
        gateway.standardOutput = FileHandle.nullDevice
        try gateway.run()

        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        client = GatewayClient(baseURL: baseURL, apnsEnvironment: .sandbox)
        try await waitUntilAnswering(baseURL.appending(path: "status"))
    }

    override func tearDown() {
        gateway?.terminate()
        gateway?.waitUntilExit()
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    func testRegisterReRegisterAndDelete() async throws {
        let first = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral", "quibdo"]))
        XCTAssertEqual(first.sensorIDs, ["chaparral", "quibdo"])

        let moved = try await client.subscribe(deviceToken: token, to: .receptors(["quibdo"]))
        XCTAssertEqual(moved.sensorIDs, ["quibdo"], "each call replaces the whole set")

        let outside = try await client.subscribe(deviceToken: token, to: .demandCell("37,-755"))
        XCTAssertEqual(outside, .init(sensorIDs: [], demandCell: "37,-755"))
        XCTAssertTrue(try storedDevices().contains(token.hexString))

        try await client.unsubscribe(deviceToken: token)
        XCTAssertFalse(try storedDevices().contains(token.hexString))
        try await client.unsubscribe(deviceToken: token) // repeatable: 204 again
    }

    func testLimitedRegistrationIsAccepted() async throws {
        let limited = GatewayClient.Subscription(sensorIDs: ["chaparral"], minMagnitude: ["chaparral": 5.5], demandCell: "44,-753")
        let registered = try await client.subscribe(deviceToken: token, to: limited)
        XCTAssertEqual(registered, .init(sensorIDs: ["chaparral"], demandCell: "44,-753"))
        let stored = try storedDevices()
        XCTAssertTrue(stored.contains("min_magnitude") && stored.contains("5.5"), "server kept the strong-only filter: \(stored)")
    }

    func testTestAlertOnlyForRegisteredPhonesOncePer10Minutes() async throws {
        do {
            _ = try await client.sendTestAlert(deviceToken: token)
            XCTFail("unregistered token must get 404")
        } catch {
            XCTAssertEqual(error, .notRegistered)
        }
        _ = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let sentAtMs = try await client.sendTestAlert(deviceToken: token)
        XCTAssertGreaterThanOrEqual(sentAtMs, before - 1000)
        do {
            _ = try await client.sendTestAlert(deviceToken: token)
            XCTFail("second test within 10 min must get 429")
        } catch {
            XCTAssertEqual(error, .tooSoon)
        }
    }

    func testTestAlertWhileTheKillSwitchIsOnSaysPaused() async throws {
        try await startGateway(extraEnvironment: ["RELAY_KILL_SWITCH": "1"])
        _ = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
        do {
            _ = try await client.sendTestAlert(deviceToken: token)
            XCTFail("kill switch must stop the test push")
        } catch {
            XCTAssertEqual(error, .relayPaused)
        }
    }

    func testStatusListsEveryPublicReceptorAndNoneIsCoveredOnAFreshGateway() async throws {
        let coverage = try await client.status()
        XCTAssertEqual(coverage["chaparral"], false, "no heartbeat yet: must not read as covered")
        XCTAssertEqual(coverage["quibdo"], false)
    }

    func testNonPublicReceptorIsRejectedWithTheServerMessage() async {
        do {
            _ = try await client.subscribe(deviceToken: token, to: .receptors(["glan"]))
            XCTFail("a canary must not be accepted")
        } catch {
            XCTAssertEqual(error, .rejected("invalid sensor_ids"))
        }
    }

    func testArrivalUploadOnlyAfterTheOperatorOptsThePhoneIn() async throws {
        try await startGateway(extraEnvironment: ["MONITOR_KEY": "contract-monitor"])
        let arrivals = [PushArrival(userInfo: ["kind": "test", "event_id": "test:\(UUID())", "sent_at_ms": NSNumber(value: 1_790_194_180_512)],
                                    receivedAt: Date(timeIntervalSince1970: 1_790_194_180.931), source: .nse, appState: .background)]

        let first = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
        XCTAssertFalse(first.telemetry)
        let refused = try await client.uploadArrivals(deviceToken: token, arrivals)
        XCTAssertEqual(refused, .telemetryOff)

        try await operatorSetsTelemetry(on: true)
        let again = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
        XCTAssertTrue(again.telemetry, "re-registering keeps the opt-in and says so")
        let stored = try await client.uploadArrivals(deviceToken: token, arrivals)
        XCTAssertEqual(stored, .stored)
        let resent = try await client.uploadArrivals(deviceToken: token, arrivals)
        XCTAssertEqual(resent, .stored, "a resend after a lost 202 is harmless")

        let tooLongID = [PushArrival(userInfo: ["kind": "test", "event_id": String(repeating: "x", count: 300),
                                                "sent_at_ms": NSNumber(value: 1)], receivedAt: .now)]
        let invalid = try await client.uploadArrivals(deviceToken: token, tooLongID)
        XCTAssertEqual(invalid, .invalid)
    }

    /// The monitor's signed POST /devices/telemetry, as the certifier sends it.
    private func operatorSetsTelemetry(on: Bool) async throws {
        let path = "/devices/telemetry"
        let body = #"{"device_token":"\#(token.hexString)","enabled":\#(on)}"#
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("\(timestamp)\nPOST \(path)\n\(body)".utf8),
                                                        using: SymmetricKey(data: Data("contract-monitor".utf8)))
            .map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: client.baseURL.appending(path: "devices/telemetry"))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue(timestamp, forHTTPHeaderField: "x-monitor-timestamp")
        request.setValue(signature, forHTTPHeaderField: "x-monitor-signature")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func file(_ name: String) -> String { dataDirectory.appending(path: name).path }

    private func storedDevices() throws -> String {
        (try? String(contentsOfFile: file("devices.json"), encoding: .utf8)) ?? ""
    }

    private func waitUntilAnswering(_ url: URL) async throws {
        for _ in 0..<50 {
            if (try? await URLSession.shared.data(from: url)) != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("gateway did not start (is node on PATH and npm install done in gateway/?)")
        throw CancellationError()
    }
}
