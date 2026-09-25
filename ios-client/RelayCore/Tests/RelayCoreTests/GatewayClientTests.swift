import Foundation
import XCTest
@testable import RelayCore

/// Local fake of the gateway: every request made through `session` lands in `respond`.
final class FakeGateway: URLProtocol {
    nonisolated(unsafe) static var respond: (URLRequest, [String: Any]) throws -> (Int, String) = { _, _ in (500, "") }
    nonisolated(unsafe) static var lastMethod: String?
    nonisolated(unsafe) static var lastBody: [String: Any] = [:]

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeGateway.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lastMethod = request.httpMethod
        Self.lastBody = body
        do {
            let (status, json) = try Self.respond(request, body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// URLSession moves the body into a stream before it reaches a URLProtocol.
    private static func readBody(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

final class GatewayClientTests: XCTestCase {
    let token = Data([0xAB, 0x01] + Array(repeating: 0x00, count: 30))
    lazy var client = GatewayClient(
        baseURL: URL(string: "https://gateway.test")!, apnsEnvironment: .sandbox, session: FakeGateway.session)

    func testSubscribeToReceptorsSendsContractBody() async throws {
        FakeGateway.respond = { request, _ in
            XCTAssertEqual(request.url?.path, "/devices")
            return (201, #"{"sensor_ids":["chaparral","quibdo"],"apns_env":"sandbox"}"#)
        }

        let registered = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral", "quibdo"]))

        XCTAssertEqual(registered, .init(sensorIDs: ["chaparral", "quibdo"], demandCell: nil))
        XCTAssertEqual(FakeGateway.lastMethod, "POST")
        XCTAssertEqual(FakeGateway.lastBody["device_token"] as? String, "ab01" + String(repeating: "00", count: 30))
        XCTAssertEqual(FakeGateway.lastBody["sensor_ids"] as? [String], ["chaparral", "quibdo"])
        XCTAssertEqual(FakeGateway.lastBody["platform"] as? String, "ios")
        XCTAssertEqual(FakeGateway.lastBody["apns_env"] as? String, "sandbox")
        XCTAssertNil(FakeGateway.lastBody["demand_cell"])
    }

    func testOutsideCoverageSendsOnlyTheDemandCell() async throws {
        FakeGateway.respond = { _, _ in (201, #"{"sensor_ids":[],"demand_cell":"37,-755","apns_env":"sandbox"}"#) }

        let registered = try await client.subscribe(deviceToken: token, to: .demandCell("37,-755"))

        XCTAssertEqual(registered, .init(sensorIDs: [], demandCell: "37,-755"))
        XCTAssertEqual(FakeGateway.lastBody["demand_cell"] as? String, "37,-755")
        XCTAssertNil(FakeGateway.lastBody["sensor_ids"], "server answers 400 when both are present")
    }

    func testLimitedSendsReceptorsStrongOnlyAndTheCellTogether() async throws {
        FakeGateway.respond = { _, _ in (201, #"{"sensor_ids":["chaparral"],"demand_cell":"44,-753","min_magnitude":{"chaparral":5.5},"apns_env":"sandbox"}"#) }

        _ = try await client.subscribe(deviceToken: token, to: .init(sensorIDs: ["chaparral"], minMagnitude: ["chaparral": 5.5], demandCell: "44,-753"))

        XCTAssertEqual(FakeGateway.lastBody["sensor_ids"] as? [String], ["chaparral"])
        XCTAssertEqual(FakeGateway.lastBody["min_magnitude"] as? [String: Double], ["chaparral": 5.5])
        XCTAssertEqual(FakeGateway.lastBody["demand_cell"] as? String, "44,-753")
    }

    func testPlainReceptorsSendNoEmptyExtras() async throws {
        FakeGateway.respond = { _, _ in (201, #"{"sensor_ids":["chaparral"]}"#) }
        _ = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
        XCTAssertNil(FakeGateway.lastBody["min_magnitude"], "the server rejects an empty min_magnitude")
        XCTAssertNil(FakeGateway.lastBody["demand_cell"])
    }

    func testUnsubscribeSendsOnlyTheToken() async throws {
        FakeGateway.respond = { _, _ in (204, "") }

        try await client.unsubscribe(deviceToken: token)

        XCTAssertEqual(FakeGateway.lastMethod, "DELETE")
        XCTAssertEqual(Array(FakeGateway.lastBody.keys), ["device_token"])
    }

    func testBadRequestIsRejectedWithTheServerMessage() async {
        FakeGateway.respond = { _, _ in (400, #"{"error":"invalid sensor_ids"}"#) }
        await assertFailure(.rejected("invalid sensor_ids"))
    }

    func testRateLimitServerErrorsAndNoNetworkAreRetryable() async {
        for status in [429, 500, 503] {
            FakeGateway.respond = { _, _ in (status, #"{"error":"too many subscriptions"}"#) }
            await assertFailure(.retryLater)
        }
        FakeGateway.respond = { _, _ in throw URLError(.notConnectedToInternet) }
        await assertFailure(.retryLater)
    }

    func testArrivalUploadSendsTheContractBody() async throws {
        let arrival = PushArrival(userInfo: ["kind": "alert", "event_id": "chaparral:1", "sent_at_ms": NSNumber(value: 1_000)],
                                  receivedAt: Date(timeIntervalSince1970: 1.5), source: .app, appState: .foreground)
        FakeGateway.respond = { request, body in
            XCTAssertEqual(request.url?.path, "/telemetry/arrivals")
            XCTAssertEqual(body["device_token"] as? String, self.token.hexString)
            let item = (body["arrivals"] as? [[String: Any]])?.first ?? [:]
            XCTAssertEqual(item["kind"] as? String, "alert")
            XCTAssertEqual(item["event_id"] as? String, "chaparral:1")
            XCTAssertEqual(item["sent_at_ms"] as? Int, 1_000)
            XCTAssertEqual(item["received_at_ms"] as? Int, 1_500)
            XCTAssertEqual(item["source"] as? String, "app")
            XCTAssertEqual(item["app_state"] as? String, "foreground")
            return (202, #"{"stored":1,"duplicates":0}"#)
        }
        let result = try await client.uploadArrivals(deviceToken: token, [arrival])
        XCTAssertEqual(result, .stored)
    }

    func testArrivalUploadStatusMapping() async throws {
        for (status, expected) in [(404, GatewayClient.TelemetryUpload.telemetryOff), (400, .invalid), (413, .invalid)] {
            FakeGateway.respond = { _, _ in (status, "{}") }
            let result = try await client.uploadArrivals(deviceToken: token, [])
            XCTAssertEqual(result, expected, "HTTP \(status)")
        }
        for status in [429, 503] {
            FakeGateway.respond = { _, _ in (status, "{}") }
            do {
                _ = try await client.uploadArrivals(deviceToken: token, [])
                XCTFail("HTTP \(status) must be retried")
            } catch {
                XCTAssertEqual(error, .retryLater)
            }
        }
    }

    func testTelemetryFlagIn201DefaultsToOff() throws {
        let off = try JSONDecoder().decode(GatewayClient.Registered.self, from: Data(#"{"sensor_ids":["a"],"apns_env":"sandbox"}"#.utf8))
        let on = try JSONDecoder().decode(GatewayClient.Registered.self, from: Data(#"{"sensor_ids":["a"],"telemetry":true}"#.utf8))
        XCTAssertFalse(off.telemetry)
        XCTAssertTrue(on.telemetry)
    }

    func testUnreadable201IsNotTakenAsRegistered() async {
        FakeGateway.respond = { _, _ in (201, "<html>proxy</html>") }
        await assertFailure(.rejected("unreadable 201 body"))
    }

    private func assertFailure(_ expected: GatewayClient.Failure, line: UInt = #line) async {
        do {
            _ = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error, expected, line: line)
        }
    }
}

final class GatewayStatusTests: XCTestCase {
    let client = GatewayClient(
        baseURL: URL(string: "https://gateway.test")!, apnsEnvironment: .sandbox, session: FakeGateway.session)

    func testStatusReadsCoveredAPNsPerReceptor() async throws {
        FakeGateway.respond = { request, _ in
            XCTAssertEqual(request.url?.path, "/status")
            return (200, #"{"now":"x","relay_enabled":true,"sensors":[{"id":"chaparral","covered":false,"covered_apns":true},{"id":"quibdo","covered":true,"covered_apns":false}]}"#)
        }
        let coverage = try await client.status()
        XCTAssertEqual(coverage, ["chaparral": true, "quibdo": false], "APNs channel, not the web push one")
    }

    func testStatusErrorOrGarbageIsRetryable() async {
        for (status, body) in [(502, ""), (200, "<html>captive portal</html>")] {
            FakeGateway.respond = { _, _ in (status, body) }
            do {
                _ = try await client.status()
                XCTFail("\(status) \(body) must not read as coverage")
            } catch {
                XCTAssertEqual(error, .retryLater)
            }
        }
    }

    func testWatchCoverageKeepsTheLastAnswerWhenTheGatewayDropsWithinGrace() async {
        nonisolated(unsafe) var calls = 0
        FakeGateway.respond = { _, _ in
            calls += 1
            return calls == 1 ? (200, #"{"sensors":[{"id":"chaparral","covered_apns":true}]}"#) : (503, "")
        }
        var emitted: [GatewayClient.ReceptorCoverage?] = []
        for await coverage in client.watchCoverage(every: .milliseconds(10)) {
            emitted.append(coverage)
            if emitted.count == 3 { break }
        }
        XCTAssertEqual(emitted, [["chaparral": true], ["chaparral": true], ["chaparral": true]])
    }

    func testWatchCoverageIsUnknownUntilTheFirstAnswer() async {
        FakeGateway.respond = { _, _ in throw URLError(.cannotConnectToHost) }
        for await coverage in client.watchCoverage(every: .milliseconds(10)) {
            XCTAssertNil(coverage)
            break
        }
    }
}

final class GatewaySensorsTests: XCTestCase {
    let client = GatewayClient(
        baseURL: URL(string: "https://gateway.test")!, apnsEnvironment: .sandbox, session: FakeGateway.session)

    func testReadsSensorsJSON() async throws {
        FakeGateway.respond = { _, _ in
            (200, #"{"version":2,"coverage":{"full_km":31,"partial_km":78},"sensors":[{"id":"chaparral","name":"Chaparral","lat":3.7,"lon":-75.4,"public":true}]}"#)
        }
        let sensors = try await client.sensors()
        XCTAssertEqual(sensors.map(\.id), ["chaparral"])
    }

    func testEmptyOrBrokenSensorsJSONIsAFailureNotAnEmptyList() async {
        for body in [#"{"coverage":{"full_km":31,"partial_km":78},"sensors":[]}"#, "<html>"] {
            FakeGateway.respond = { _, _ in (200, body) }
            do {
                _ = try await client.sensors()
                XCTFail("must throw for \(body)")
            } catch {
                XCTAssertEqual(error, .retryLater)
            }
        }
    }
}
