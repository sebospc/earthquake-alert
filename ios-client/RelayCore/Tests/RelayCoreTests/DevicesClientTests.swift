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

final class DevicesClientTests: XCTestCase {
    let token = Data([0xAB, 0x01] + Array(repeating: 0x00, count: 30))
    lazy var client = DevicesClient(
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

    func testUnreadable201IsNotTakenAsRegistered() async {
        FakeGateway.respond = { _, _ in (201, "<html>proxy</html>") }
        await assertFailure(.rejected("unreadable 201 body"))
    }

    private func assertFailure(_ expected: DevicesClient.Failure, line: UInt = #line) async {
        do {
            _ = try await client.subscribe(deviceToken: token, to: .receptors(["chaparral"]))
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error, expected, line: line)
        }
    }
}
