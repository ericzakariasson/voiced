// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoicedKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "VoicedKit", targets: ["VoicedKit"]),
    ],
    targets: [
        .target(name: "VoicedKit"),
        .testTarget(name: "VoicedKitTests", dependencies: ["VoicedKit"]),
    ],
    swiftLanguageModes: [.v6]
)
