// swift-tools-version: 6.2
import PackageDescription

// Logic with no UI, tested with `swift test` on the Mac (no simulator needed).
let package = Package(
    name: "RelayCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "RelayCore", targets: ["RelayCore"])],
    targets: [
        .target(name: "RelayCore"),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"]),
    ]
)
