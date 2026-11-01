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
            url: "https://github.com/hotcodepush-team/core-ios/releases/download/0.3.0/HotCodePushCore.xcframework.zip",
            checksum: "6d12e0613ce25748963f0ff492a6e33687a25bf291d94e2950d5b1867bbc3685"),
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
