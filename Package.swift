// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KaizenKit",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
            ]
        ),
        .testTarget(
            name: "KaizenKitTests",
            dependencies: ["KaizenKit"],
            path: "Tests/KaizenKitTests"
        ),
    ]
)
