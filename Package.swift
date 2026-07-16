// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Loom",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "Loom", targets: ["Loom"])
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/yoga.git", from: "3.2.1")
    ],
    targets: [
        .target(
            name: "Loom",
            dependencies: [.product(name: "yoga", package: "yoga")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "LoomTests",
            dependencies: ["Loom"]
        )
    ]
)
