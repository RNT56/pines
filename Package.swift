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
        .executable(name: "PinesCoreTestRunner", targets: ["PinesCoreTestRunner"]),
    ],
    targets: [
        .target(
            name: "PinesCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "PinesCoreTestRunner",
            dependencies: ["PinesCore"]
        ),
    ]
)
