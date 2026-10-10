// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeonPup",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NeonPupCore"),
        .target(name: "NeonPupKit", dependencies: ["NeonPupCore"]),
        .executableTarget(name: "NeonPup", dependencies: ["NeonPupKit", "NeonPupCore"]),
        .executableTarget(name: "NeonPupHelper", dependencies: ["NeonPupCore"]),
        .testTarget(name: "NeonPupCoreTests", dependencies: ["NeonPupCore"]),
        .testTarget(name: "NeonPupKitTests", dependencies: ["NeonPupKit", "NeonPupCore"]),
    ]
)
