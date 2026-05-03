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
        // Apple's Swift-DocC plugin — enables `swift package generate-documentation`
        // and `swift package --disable-sandbox preview-documentation --target AetherUI`.
        // The DocC catalog itself lives at `Sources/AetherUI/AetherUI.docc/`.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
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
            ],
            path: "Sources/AetherUI",
            resources: [
                // Metal sources for the DustEffectLayer port. SPM picks
                // up *.metal files inside the target and compiles them
                // into a `default.metallib` accessible via Bundle.module.
                .process("ListView/DustEffect/Metal")
            ]
        ),
    ]
)
