import Foundation

/// POST and DELETE /devices, per docs/ios-contract.md.
public struct DevicesClient: Sendable {
    public enum APNsEnvironment: String, Sendable { case production, sandbox }

    public enum Subscription: Equatable, Sendable {
        case receptors([String])
        /// "floor(lat*10),floor(lon*10)", only when no public receptor is within `partial_km`.
        case demandCell(String)
    }

    public struct Registered: Decodable, Equatable, Sendable {
        public let sensorIDs: [String]
        public let demandCell: String?

        enum CodingKeys: String, CodingKey { case sensorIDs = "sensor_ids", demandCell = "demand_cell" }
    }

    public enum Failure: Error, Equatable {
        /// 4xx: the request is wrong, sending it again will not help.
        case rejected(String)
        /// 429, 5xx or no network: retry with backoff, show "not registered" meanwhile.
        case retryLater
    }

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
        switch subscription {
        case .receptors(let sensorIDs): body.sensorIDs = sensorIDs
        case .demandCell(let cell): body.demandCell = cell
        }
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

    private func send(_ method: String, _ body: RequestBody) async throws(Failure) -> Data {
        var request = URLRequest(url: baseURL.appending(path: "devices"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .retryLater
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 429, 500...:
            throw .retryLater
        default:
            let serverMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw .rejected(serverMessage ?? "HTTP \(status)")
        }
    }

    /// Optional fields left nil are omitted, so a demand-cell call never carries `sensor_ids`.
    private struct RequestBody: Encodable {
        let deviceToken: String
        var sensorIDs: [String]?
        var demandCell: String?
        var platform: String?
        var apnsEnv: String?

        enum CodingKeys: String, CodingKey {
            case deviceToken = "device_token", sensorIDs = "sensor_ids", demandCell = "demand_cell"
            case platform, apnsEnv = "apns_env"
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
