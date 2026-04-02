// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BiteFM",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BiteFMCore", targets: ["BiteFMCore"]),
        .executable(name: "BiteFMMac", targets: ["BiteFMMac"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BiteFMCore",
            dependencies: [],
            path: "Sources/BiteFMCore",
            resources: [.process("Assets.xcassets")]
        ),
        .executableTarget(
            name: "BiteFMMac",
            dependencies: ["BiteFMCore"],
            path: "Sources/BiteFMMac"
        ),
        .testTarget(
            name: "BiteFMTests",
            dependencies: ["BiteFMCore"],
            path: "Tests/BiteFMTests"
        )
    ]
)
