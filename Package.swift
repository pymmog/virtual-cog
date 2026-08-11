// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualCog",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VirtualCogCore", targets: ["VirtualCogCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "VirtualCogCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "CryptoSwift", package: "CryptoSwift")
            ],
            path: "VirtualCog",
            exclude: [
                "App",
                "UI",
                "Devices/Shared/zwift.proto"
            ],
            resources: [
                .copy("../Resources/Courses"),
                .copy("../Resources/Fixtures")
            ]
        ),
        .testTarget(
            name: "VirtualCogCoreTests",
            dependencies: ["VirtualCogCore"],
            path: "Tests/VirtualCogCoreTests"
        )
    ]
)
