// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HonkHonk",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HonkHonk", targets: ["HonkHonk"]),
    ],
    targets: [
        .target(name: "HonkHonk"),
        .testTarget(name: "HonkHonkTests", dependencies: ["HonkHonk"]),
    ],
    swiftLanguageModes: [.v6]
)
