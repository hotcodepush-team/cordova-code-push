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
            url: "https://github.com/hotcodepush-team/core-ios/releases/download/0.2.0/HotCodePushCore.xcframework.zip",
            checksum: "cb33348bd301eebcbae22532efb235e2136141f18a35b6fc190bc1724641c0bf"),
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
