// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoersaalB",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HoersaalB", targets: ["HoersaalB"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "HoersaalB",
            dependencies: [],
            path: "Sources/HoersaalB"
        )
    ]
)

