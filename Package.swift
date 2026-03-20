// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BiteFM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BiteFM", targets: ["BiteFM"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BiteFM",
            dependencies: [],
            path: "Sources/BiteFM",
            resources: [.process("Assets.xcassets")]
        ),
        .testTarget(
            name: "BiteFMTests",
            dependencies: ["BiteFM"],
            path: "Tests/BiteFMTests"
        )
    ]
)

