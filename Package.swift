// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWineLauncher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacWineLauncher", targets: ["MacWineLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "MacWineLauncher",
            path: "Sources/MacWineLauncher"
        ),
        .testTarget(
            name: "MacWineLauncherTests",
            dependencies: ["MacWineLauncher"],
            path: "Tests/MacWineLauncherTests"
        )
    ]
)
