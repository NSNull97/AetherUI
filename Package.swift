// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AetherUI",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "AetherUI",
            targets: ["AetherUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit.git", from: "5.7.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
        .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "AetherUIBridging",
            path: "Sources/AetherUIBridging",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AetherUI",
            dependencies: [
                "AetherUIBridging",
                "SnapKit",
                "AssociatedObject",
            ],
            path: "Sources/AetherUI",
            resources: [
                .process("ContextMenu/Metal"),
                .process("ListView/DustEffect/Metal")
            ]
        ),
        .testTarget(
            name: "AetherUITests",
            dependencies: ["AetherUI"],
            path: "Tests/AetherUITests"
        ),
    ]
)
