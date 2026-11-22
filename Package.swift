// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quarry",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Quarry", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "QuarryTests", dependencies: ["Quarry"], swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
