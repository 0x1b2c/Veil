// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "veil",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../VeilCore")
    ],
    targets: [
        .executableTarget(
            name: "veil",
            dependencies: [.product(name: "VeilCore", package: "VeilCore")]
        )
    ]
)
