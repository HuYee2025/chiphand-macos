// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ChipHand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GestureControlCore", targets: ["GestureControlCore"]),
        .executable(name: "ChipHand", targets: ["ChipHand"]),
    ],
    targets: [
        .target(name: "GestureControlCore"),
        .executableTarget(
            name: "ChipHand",
            dependencies: ["GestureControlCore"],
            path: "Sources/GestureControlApp"
        ),
        .executableTarget(
            name: "GestureControlCoreChecks",
            dependencies: ["GestureControlCore"]
        ),
        .testTarget(
            name: "GestureControlCoreTests",
            dependencies: ["GestureControlCore"]
        ),
    ]
)
