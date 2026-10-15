// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VeilCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeilCore", targets: ["VeilCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/swift-toml", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "VeilCore",
            dependencies: [.product(name: "TOML", package: "swift-toml")],
            plugins: [.plugin(name: "BuildVersionPlugin")]
        ),
        .testTarget(name: "VeilCoreTests", dependencies: ["VeilCore"]),
        .plugin(
            name: "BuildVersionPlugin",
            capability: .buildTool()
        ),
    ]
)
