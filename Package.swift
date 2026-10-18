// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Flaran",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "FlaranKit", swiftSettings: settings),
        .executableTarget(name: "Flaran", dependencies: ["FlaranKit"], swiftSettings: settings),
        .testTarget(name: "FlaranKitTests", dependencies: ["FlaranKit"], swiftSettings: settings),
    ]
)
