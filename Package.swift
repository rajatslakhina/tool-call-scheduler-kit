// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ToolCallSchedulerKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ToolCallSchedulerKit", targets: ["ToolCallSchedulerKit"]),
        .executable(name: "ToolCallSchedulerDemo", targets: ["ToolCallSchedulerDemo"])
    ],
    targets: [
        .target(
            name: "ToolCallSchedulerKit",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "ToolCallSchedulerDemo",
            dependencies: ["ToolCallSchedulerKit"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ToolCallSchedulerKitTests",
            dependencies: ["ToolCallSchedulerKit"]
        )
    ]
)
