// swift-tools-version: 5.9
import PackageDescription

// cordova-ios adds a Swift package plugin to the app under the plugin id, so the package and its product carry it.
let package = Package(
    name: "@hotcodepush/cordova-code-push",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "@hotcodepush/cordova-code-push",
            targets: ["HotCodePushCordova"])
    ],
    dependencies: [
        .package(url: "https://github.com/apache/cordova-ios.git", from: "8.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "HotCodePushCore",
            url: "https://github.com/hotcodepush-team/core-ios/releases/download/0.4.0/HotCodePushCore.xcframework.zip",
            checksum: "0ac3338f1f8e0e2c4c79cf5cb00d70a078fd25a17e2586fc7ff1edee7166d941"),
        .target(
            name: "HotCodePushCordova",
            dependencies: [
                "HotCodePushCore",
                .product(name: "Cordova", package: "cordova-ios")
            ],
            path: "src/ios"),
        .testTarget(
            name: "HotCodePushCordovaTests",
            dependencies: ["HotCodePushCordova"],
            path: "tests/ios")
    ]
)
