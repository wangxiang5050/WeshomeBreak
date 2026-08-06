// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrillBreakCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "GrillBreakCore",
            targets: ["GrillBreakCore"]
        )
    ],
    targets: [
        .target(
            name: "GrillBreakCore"
        ),
        .testTarget(
            name: "GrillBreakCoreTests",
            dependencies: ["GrillBreakCore"]
        )
    ]
)
