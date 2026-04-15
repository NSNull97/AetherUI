// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TelegramNavigationKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "TelegramNavigationKit",
            targets: ["TelegramNavigationKit"]
        ),
    ],
    targets: [
        .target(
            name: "TelegramNavigationKit",
            path: "Sources/TelegramNavigationKit"
        ),
    ]
)
