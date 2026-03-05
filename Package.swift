// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PlantKeeper",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlantKeeperCore", targets: ["PlantKeeperCore"]),
        .executable(name: "PlantKeeperApp", targets: ["PlantKeeperApp"])
    ],
    targets: [
        .target(
            name: "PlantKeeperCore",
            path: "Sources/PlantKeeperCore"
        ),
        .executableTarget(
            name: "PlantKeeperApp",
            dependencies: ["PlantKeeperCore"],
            path: "Sources/PlantKeeperApp"
        ),
        .testTarget(
            name: "PlantKeeperCoreTests",
            dependencies: ["PlantKeeperCore"],
            path: "Tests/PlantKeeperCoreTests"
        ),
        .testTarget(
            name: "PlantKeeperAppTests",
            dependencies: ["PlantKeeperApp", "PlantKeeperCore"],
            path: "Tests/PlantKeeperAppTests"
        )
    ]
)
