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
        .package(url: "https://github.com/hotcodepush-team/protocol-ios.git", revision: "457635bfb1d248af8a87df374a4694f43e8253f9")
    ],
    targets: [
        .target(
            name: "HotCodePushCordova",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .product(name: "HotCodePushProtocol", package: "protocol-ios")
            ],
            path: "src/ios")
    ]
)
