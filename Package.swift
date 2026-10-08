// swift-tools-version: 5.9
import PackageDescription

// The package and its product carry the plugin's id: cordova-ios adds a Swift package plugin to the app under that name.
let package = Package(
    name: "@hotcodepush/cordova-code-push",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "@hotcodepush/cordova-code-push",
            targets: ["HotCodePushCordova"])
    ],
    dependencies: [
        .package(url: "https://github.com/apache/cordova-ios.git", from: "8.0.0"),
        .package(url: "https://github.com/hotcodepush-team/core-ios.git", revision: "05389b3add61baf732e119f36ca1aa6b7bf4339d")
    ],
    targets: [
        .target(
            name: "HotCodePushCordova",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .product(name: "HotCodePushCore", package: "core-ios")
            ],
            path: "src/ios")
    ]
)
