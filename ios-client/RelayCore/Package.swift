// swift-tools-version: 6.2
import PackageDescription

// Logic with no UI, tested with `swift test` on the Mac (no simulator needed).
let package = Package(
    name: "RelayCore",
    defaultLocalization: "es",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "RelayCore", targets: ["RelayCore"])],
    targets: [
        .target(name: "RelayCore", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"]),
    ]
)
