// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoyuReader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MoyuReader", targets: ["MoyuReader"])
    ],
    targets: [
        .target(name: "MoyuReaderCore"),
        .executableTarget(
            name: "MoyuReader",
            dependencies: ["MoyuReaderCore"]
        ),
        .testTarget(
            name: "MoyuReaderCoreTests",
            dependencies: ["MoyuReaderCore"]
        )
    ]
)
