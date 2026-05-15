// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PinesCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PinesCore", targets: ["PinesCore"]),
        .library(name: "PinesHubXetSupport", targets: ["PinesHubXetSupport"]),
        .executable(name: "PinesCoreTestRunner", targets: ["PinesCoreTestRunner"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/huggingface/swift-huggingface.git",
            from: "0.9.0",
            traits: [.defaults, "Xet"]
        ),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "PinesCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "PinesHubXetSupport",
            dependencies: [
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ]
        ),
        .executableTarget(
            name: "PinesCoreTestRunner",
            dependencies: ["PinesCore"]
        ),
    ]
)
