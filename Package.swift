// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrystalUI",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CrystalUI",
            targets: ["CrystalUI"]
        ),
    ],
    targets: [
        .target(
            name: "CrystalUI",
            path: "Sources/CrystalUI"
        ),
    ]
)
