// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VeilCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeilCore", targets: ["VeilCore"])
    ],
    targets: [
        .target(name: "VeilCore"),
        .testTarget(name: "VeilCoreTests", dependencies: ["VeilCore"]),
    ]
)
