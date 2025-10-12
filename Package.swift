// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AmbiMux",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AmbiMuxCore",
            targets: ["AmbiMuxCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2")
    ],
    targets: [
        .target(
            name: "AmbiMuxCore",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(
            name: "AmbiMuxMain",
            dependencies: [
                "AmbiMuxCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "AmbiMuxTests",
            dependencies: [
                "AmbiMuxCore"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
