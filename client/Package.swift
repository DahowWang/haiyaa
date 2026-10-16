// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceType",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "VoiceType", path: "Sources/VoiceType"),
        .testTarget(name: "VoiceTypeTests", dependencies: ["VoiceType"])
    ],
    swiftLanguageModes: [.v5]
)
