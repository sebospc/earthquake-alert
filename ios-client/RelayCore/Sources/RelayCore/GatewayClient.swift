import Foundation

/// POST and DELETE /devices, GET /status, per docs/ios-contract.md.
public struct GatewayClient: Sendable {
    public enum APNsEnvironment: String, Sendable { case production, sandbox }

    /// What POST /devices asks for. Either receptors (optionally with strong-only ones and, when
    /// the level is "limited", the demand cell too) or only a demand cell.
    public struct Subscription: Codable, Equatable, Sendable {
        public var sensorIDs: [String]
        /// Receptors followed only for strong quakes, with their minimum magnitude.
        public var minMagnitude: [String: Double]
        /// "floor(lat*10),floor(lon*10)". Alone when nothing is eligible, with receptors when "limited".
        public var demandCell: String?

        public init(sensorIDs: [String], minMagnitude: [String: Double] = [:], demandCell: String? = nil) {
            self.sensorIDs = sensorIDs
            self.minMagnitude = minMagnitude
            self.demandCell = demandCell
        }

        public static func receptors(_ ids: [String]) -> Self { Self(sensorIDs: ids) }
        public static func demandCell(_ cell: String) -> Self { Self(sensorIDs: [], demandCell: cell) }
    }

    public struct Registered: Decodable, Equatable, Sendable {
        public let sensorIDs: [String]
        public let demandCell: String?
        /// The operator opted this phone in to arrival telemetry. Absent means off.
        public let telemetry: Bool

        public init(sensorIDs: [String], demandCell: String?, telemetry: Bool = false) {
            self.sensorIDs = sensorIDs
            self.demandCell = demandCell
            self.telemetry = telemetry
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sensorIDs = try container.decode([String].self, forKey: .sensorIDs)
            demandCell = try container.decodeIfPresent(String.self, forKey: .demandCell)
            telemetry = try container.decodeIfPresent(Bool.self, forKey: .telemetry) ?? false
        }

        enum CodingKeys: String, CodingKey { case sensorIDs = "sensor_ids", demandCell = "demand_cell", telemetry }
    }

    public enum Failure: Error, Equatable {
        /// 4xx: the request is wrong, sending it again will not help.
        case rejected(String)
        /// 429, 5xx or no network: retry with backoff, show "not registered" meanwhile.
        case retryLater
    }

    /// `covered_apns` per receptor. Kill switch, stale listener and APNs outages are already folded in by the server.
    public typealias ReceptorCoverage = [String: Bool]

    let baseURL: URL
    let apnsEnvironment: APNsEnvironment
    let session: URLSession

    public init(baseURL: URL, apnsEnvironment: APNsEnvironment, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apnsEnvironment = apnsEnvironment
        self.session = session
    }

    /// Replaces the whole set of receptors for this token.
    public func subscribe(deviceToken: Data, to subscription: Subscription) async throws(Failure) -> Registered {
        var body = RequestBody(deviceToken: deviceToken.hexString, platform: "ios", apnsEnv: apnsEnvironment.rawValue)
        // Empty fields are left out: the server rejects an empty sensor_ids or min_magnitude.
        body.sensorIDs = subscription.sensorIDs.isEmpty ? nil : subscription.sensorIDs
        body.minMagnitude = subscription.minMagnitude.isEmpty ? nil : subscription.minMagnitude
        body.demandCell = subscription.demandCell
        let data = try await send("POST", body)
        guard let registered = try? JSONDecoder().decode(Registered.self, from: data) else {
            throw .rejected("unreadable 201 body")
        }
        return registered
    }

    /// Safe to repeat: the server answers 204 whether the token exists or not.
    public func unsubscribe(deviceToken: Data) async throws(Failure) {
        _ = try await send("DELETE", RequestBody(deviceToken: deviceToken.hexString))
    }

    public func status() async throws(Failure) -> ReceptorCoverage {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: baseURL.appending(path: "status"))
        } catch {
            throw .retryLater
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(StatusBody.self, from: data)
        else { throw .retryLater }
        return Dictionary(status.sensors.map { ($0.id, $0.coveredAPNs) }, uniquingKeysWith: { first, _ in first })
    }

    /// Public receptors and coverage radii. Throws `.retryLater` on anything unreadable: an empty
    /// list must never be mistaken for "no receptors near you".
    public func sensors() async throws(Failure) -> [Sensor] {
        guard let (data, response) = try? await session.data(from: baseURL.appending(path: "sensors.json")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let file = try? JSONDecoder().decode(SensorsFile.self, from: data),
              !file.sensors.isEmpty
        else { throw .retryLater }
        return file.sensors
    }

    /// Emits the coverage to show every `interval` while the app is open, grace included (see `CoverageTracker`).
    /// ponytail: fixed interval while open; the background/push-driven refresh comes with the notification decision.
    public func watchCoverage(every interval: Duration = .seconds(60)) -> AsyncStream<ReceptorCoverage?> {
        AsyncStream { continuation in
            let polling = Task {
                var tracker = CoverageTracker()
                while !Task.isCancelled {
                    if let answer = try? await status() { tracker.record(answer, at: .now) }
                    continuation.yield(tracker.coverage(at: .now))
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in polling.cancel() }
        }
    }

    private struct StatusBody: Decodable {
        struct Sensor: Decodable {
            let id: String
            let coveredAPNs: Bool
            enum CodingKeys: String, CodingKey { case id, coveredAPNs = "covered_apns" }
        }
        let sensors: [Sensor]
    }

    private func send(_ method: String, _ body: RequestBody) async throws(Failure) -> Data {
        guard let (status, data) = await perform(method, path: "devices", body) else { throw .retryLater }
        switch status {
        case 200..<300:
            return data
        case 429, 500...:
            throw .retryLater
        default:
            throw .rejected(Self.serverError(data) ?? "HTTP \(status)")
        }
    }

    public enum TestAlertFailure: Error, Equatable {
        case notRegistered
        /// 429, per token (one per 10 min) or per IP.
        case tooSoon
        /// 503 "relay paused": the kill switch is on, nothing is sent to anyone.
        case relayPaused
        case rejected(String)
        /// No network, or a 5xx other than the kill switch.
        case unreachable
    }

    /// POST /devices/test. Returns the gateway's `sent_at_ms`.
    public func sendTestAlert(deviceToken: Data) async throws(TestAlertFailure) -> Int64 {
        guard let (status, data) = await perform("POST", path: "devices/test", RequestBody(deviceToken: deviceToken.hexString))
        else { throw .unreachable }
        switch status {
        case 202:
            struct Accepted: Decodable { let sent_at_ms: Int64 }
            guard let accepted = try? JSONDecoder().decode(Accepted.self, from: data) else {
                throw .rejected("unreadable 202 body")
            }
            return accepted.sent_at_ms
        case 404: throw .notRegistered
        case 429: throw .tooSoon
        case 503 where Self.serverError(data) == "relay paused": throw .relayPaused
        case 500...: throw .unreachable
        default: throw .rejected(Self.serverError(data) ?? "HTTP \(status)")
        }
    }

    public enum TelemetryUpload: Equatable, Sendable {
        case stored
        /// 400 or 413: this batch will never be accepted. Drop it and go on.
        case invalid
        /// 404: not registered or not opted in. Stop until a 201 says `telemetry: true` again.
        case telemetryOff
    }

    /// POST /telemetry/arrivals, at most `ArrivalUploader.batchSize` items. Throws `.retryLater`
    /// on 429, 5xx or no network.
    public func uploadArrivals(deviceToken: Data, _ arrivals: [PushArrival]) async throws(Failure) -> TelemetryUpload {
        struct Item: Encodable {
            let kind: String, event_id: String, sent_at_ms: Int64, received_at_ms: Int64, source: String, app_state: String
        }
        struct Body: Encodable { let device_token: String; let arrivals: [Item] }
        let items = arrivals.compactMap { arrival -> Item? in
            guard let kind = arrival.kind, let eventID = arrival.eventID, let sentAtMs = arrival.sentAtMs else { return nil }
            return Item(kind: kind, event_id: eventID, sent_at_ms: sentAtMs, received_at_ms: arrival.receivedAtMs,
                        source: (arrival.source ?? .nse).rawValue, app_state: (arrival.appState ?? .unknown).rawValue)
        }
        guard let (status, _) = await perform("POST", path: "telemetry/arrivals",
                                                Body(device_token: deviceToken.hexString, arrivals: items))
        else { throw .retryLater }
        switch status {
        case 200..<300: return .stored
        case 404: return .telemetryOff
        case 429, 500...: throw .retryLater
        default: return .invalid
        }
    }

    /// nil when the request never got an HTTP answer.
    private func perform(_ method: String, path: String, _ body: some Encodable) async -> (status: Int, data: Data)? {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        return (status, data)
    }

    private static func serverError(_ data: Data) -> String? {
        (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
    }

    /// Optional fields left nil are omitted, so a demand-cell call never carries `sensor_ids`.
    private struct RequestBody: Encodable {
        let deviceToken: String
        var sensorIDs: [String]?
        var minMagnitude: [String: Double]?
        var demandCell: String?
        var platform: String?
        var apnsEnv: String?

        enum CodingKeys: String, CodingKey {
            case deviceToken = "device_token", sensorIDs = "sensor_ids", minMagnitude = "min_magnitude", demandCell = "demand_cell"
            case platform, apnsEnv = "apns_env"
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
