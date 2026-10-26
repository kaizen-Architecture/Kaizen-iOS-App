// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KaizenKit",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "KaizenKit",
            targets: ["KaizenKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KaizenKit",
            dependencies: [],
            path: "Sources/KaizenKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "KaizenKitTests",
            dependencies: ["KaizenKit"],
            path: "Tests/KaizenKitTests"
        ),
    ]
)
