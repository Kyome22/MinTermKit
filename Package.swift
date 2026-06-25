// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "MinTermKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "MinTermKit",
            targets: ["MinTermKit"]
        ),
    ],
    targets: [
        .target(
            name: "MinTermCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MinTermProcess",
            dependencies: ["MinTermCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MinTermKit",
            dependencies: ["MinTermCore", "MinTermProcess"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MinTermCoreTests",
            dependencies: ["MinTermCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MinTermKitTests",
            dependencies: ["MinTermKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
