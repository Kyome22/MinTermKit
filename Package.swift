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
            name: "MinTermKit",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MinTermKitTests",
            dependencies: ["MinTermKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
