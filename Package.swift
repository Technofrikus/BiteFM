// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ByteFM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ByteFM", targets: ["ByteFM"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ByteFM",
            dependencies: [],
            path: "Sources/ByteFM"
        )
    ]
)

