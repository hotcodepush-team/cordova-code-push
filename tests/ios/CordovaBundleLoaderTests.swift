import HotCodePushCore
import XCTest
@testable import HotCodePushCordova

/// `CordovaBundleLoader.servedFile(forRequestPath:)`: which requests a running bundle answers, with which of its files,
/// and which it leaves to Cordova. The path is the request URL's `path`, as the plugin passes it: percent-decoded, with its leading slash.
final class CordovaBundleLoaderTests: XCTestCase {
    private let loader = CordovaBundleLoader(store: UserDefaultsStore(defaults: UserDefaults(suiteName: "CordovaBundleLoaderTests")!), startPage: "index.html", reloadStartPage: {})

    func testShouldLeaveTheRequestToCordovaWhenTheStartHasNotDecided() {
        let servedFile = loader.servedFile(forRequestPath: "/index.html")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveTheRequestToCordovaWhenTheEmbeddedBundleRuns() {
        loader.beginServing(bundleId: nil)

        let servedFile = loader.servedFile(forRequestPath: "/index.html")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveCordovaJsToCordovaWhenABundleRuns() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/cordova.js")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveCordovaPluginsJsToCordovaWhenABundleRuns() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/cordova_plugins.js")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveAPluginFileToCordovaWhenABundleRuns() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/plugins/cordova-plugin-device/www/device.js")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveAnAppFileToCordovaWhenABundleRuns() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/_app_file_/var/mobile/Documents/photo.jpg")

        XCTAssertNil(servedFile)
    }

    func testShouldAnswerTheStartPageWhenThePathIsEmpty() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "")

        assertServedFile(servedFile, equals: .file(bundleFile("index.html", bundleId: "b1")))
    }

    func testShouldAnswerTheStartPageWhenThePathIsTheRoot() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/")

        assertServedFile(servedFile, equals: .file(bundleFile("index.html", bundleId: "b1")))
    }

    func testShouldAnswerTheStartPageWhenThePathHasNoExtension() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/settings")

        assertServedFile(servedFile, equals: .file(bundleFile("index.html", bundleId: "b1")))
    }

    func testShouldAnswerTheBundleFileAtThePath() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/assets/app.js")

        assertServedFile(servedFile, equals: .file(bundleFile("assets/app.js", bundleId: "b1")))
    }

    func testShouldAnswerNotFoundWhenThePathClimbsOutOfTheBundle() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/../b2/index.html")

        assertServedFile(servedFile, equals: .missing)
    }

    func testShouldAnswerNotFoundWhenThePathClimbsIntoABundleWhoseIdStartsWithTheRunningOne() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/../b10/index.html")

        assertServedFile(servedFile, equals: .missing)
    }

    func testShouldAnswerTheBundleFileWhenThePathClimbsBackIntoTheBundle() {
        loader.beginServing(bundleId: "b1")

        let servedFile = loader.servedFile(forRequestPath: "/assets/../index.html")

        assertServedFile(servedFile, equals: .file(bundleFile("index.html", bundleId: "b1")))
    }

    private func bundleFile(_ relativePath: String, bundleId: String) -> URL {
        return loader.projectionDirectory(bundleId: bundleId).appendingPathComponent(relativePath)
    }

    /// `ServedFile` is not Equatable: a file compares by its path.
    private func assertServedFile(_ actual: ServedFile?, equals expected: ServedFile, file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, expected) {
        case let (.file(actualURL)?, .file(expectedURL)):
            XCTAssertEqual(actualURL.path, expectedURL.path, file: file, line: line)
        case (.missing?, .missing):
            break
        default:
            XCTFail("\(String(describing: actual)) is not \(expected)", file: file, line: line)
        }
    }
}
