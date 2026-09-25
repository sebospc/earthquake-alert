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
        ]) { _, test in test }
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
