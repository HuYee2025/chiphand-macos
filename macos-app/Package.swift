// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GestureControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GestureControlCore", targets: ["GestureControlCore"]),
        .executable(name: "GestureControl", targets: ["GestureControlApp"]),
    ],
    targets: [
        .target(name: "GestureControlCore"),
        .executableTarget(
            name: "GestureControlApp",
            dependencies: ["GestureControlCore"]
        ),
        .executableTarget(
            name: "GestureControlCoreChecks",
            dependencies: ["GestureControlCore"]
        ),
    ]
)
