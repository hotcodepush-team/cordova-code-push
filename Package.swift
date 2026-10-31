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
            url: "https://github.com/hotcodepush-team/core-ios/releases/download/0.1.0/HotCodePushCore.xcframework.zip",
            checksum: "a545ca21afa9ffb791484e17fbd2ea49e1f28340931cc5fe0526791debab4d1f"),
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
