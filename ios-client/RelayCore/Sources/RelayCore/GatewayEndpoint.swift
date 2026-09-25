import Foundation

/// Which gateway a build talks to. Debug builds never fall back to a live host: without an
/// explicit `-gateway <url>` they use a local dry-run gateway, so a simulator run cannot write
/// to staging by accident (it did once, 2026-09-25).
public enum GatewayEndpoint {
    public static let local = URL(string: "http://localhost:8787")!
    // ponytail: staging host until there is a production one.
    public static let release = URL(string: "https://d1o3i68tksfjqi.cloudfront.net")!

    public static func url(isDebugBuild: Bool, launchOverride: String?) -> URL {
        guard isDebugBuild else { return release }
        return launchOverride.flatMap(URL.init(string:)) ?? local
    }
}
