// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PinesCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "PinesCore", targets: ["PinesCore"]),
        .library(name: "PinesHubXetSupport", targets: ["PinesHubXetSupport"]),
        .library(name: "PinesWatchSupport", targets: ["PinesWatchSupport"]),
        .executable(name: "PinesCoreTestRunner", targets: ["PinesCoreTestRunner"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/huggingface/swift-huggingface.git",
            from: "0.9.0",
            traits: [.defaults, "Xet"]
        ),
        // EventSource 1.4.x enables AsyncHTTPClient traits that currently break Xcode's simulator build.
        .package(url: "https://github.com/mattt/EventSource.git", exact: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "PinesCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/PinesCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "PinesHubXetSupport",
            dependencies: [
                .product(name: "EventSource", package: "EventSource"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/PinesHubXetSupport"
        ),
        .target(
            name: "PinesWatchSupport",
            dependencies: [],
            path: "Sources/PinesWatchSupport",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "PinesCoreTestRunner",
            dependencies: ["PinesCore"]
        ),
        .testTarget(
            name: "PinesCoreTests",
            dependencies: ["PinesCore"]
        ),
        .testTarget(
            name: "PinesWatchSupportTests",
            dependencies: ["PinesWatchSupport"]
        ),
    ]
)
