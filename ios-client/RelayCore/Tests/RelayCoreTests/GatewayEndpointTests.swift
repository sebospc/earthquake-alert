import XCTest
@testable import RelayCore

final class GatewayEndpointTests: XCTestCase {
    func testDebugWithoutOverrideNeverReachesALiveHost() {
        let url = GatewayEndpoint.url(isDebugBuild: true, launchOverride: nil)
        XCTAssertEqual(url.host(), "localhost")
        XCTAssertNotEqual(url, GatewayEndpoint.release)
    }

    func testDebugUsesAnExplicitOverride() {
        XCTAssertEqual(GatewayEndpoint.url(isDebugBuild: true, launchOverride: "https://gateway.test"), URL(string: "https://gateway.test"))
    }

    func testReleaseIgnoresLaunchArguments() {
        XCTAssertEqual(GatewayEndpoint.url(isDebugBuild: false, launchOverride: "http://evil.test"), GatewayEndpoint.release)
    }
}
