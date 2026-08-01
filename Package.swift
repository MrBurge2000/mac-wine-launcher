// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SteamBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SteamBridge", targets: ["SteamBridge"])
    ],
    targets: [
        .executableTarget(
            name: "SteamBridge",
            path: "Sources/SteamBridge"
        ),
        .testTarget(
            name: "SteamBridgeTests",
            dependencies: ["SteamBridge"],
            path: "Tests/SteamBridgeTests"
        )
    ]
)
