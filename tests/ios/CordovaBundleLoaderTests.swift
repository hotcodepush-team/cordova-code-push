import HotCodePushCore
import XCTest
@testable import HotCodePushCordova

// Request paths are the URL's `path` as the plugin passes it: percent-decoded, with a leading slash.
final class CordovaBundleLoaderTests: XCTestCase {
    private let loader = CordovaBundleLoaderTests.makeLoader()

    func testShouldLeaveTheRequestToCordovaWhenTheStartHasNotDecided() {
        let servedFile = loader.servedFile(forRequestPath: "/index.html")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveTheRequestToCordovaWhenTheEmbeddedBundleRuns() {
        loader.beginServing(bundleId: nil)

        let servedFile = loader.servedFile(forRequestPath: "/index.html")

        XCTAssertNil(servedFile)
    }

    func testShouldLeaveTheFrameworkFilesToCordovaWhenABundleRuns() {
        loader.beginServing(bundleId: "b1")

        for path in ["/cordova.js", "/cordova_plugins.js", "/plugins/cordova-plugin-device/www/device.js", "/_app_file_/var/mobile/Documents/photo.jpg"] {
            XCTAssertNil(loader.servedFile(forRequestPath: path), path)
        }
    }

    func testShouldAnswerTheStartPageWhenThePathNamesNoFile() {
        loader.beginServing(bundleId: "b1")

        for path in ["", "/", "/settings"] {
            assertServedFile(loader.servedFile(forRequestPath: path), equals: .file(bundleFile("index.html", bundleId: "b1")))
        }
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

    private static func makeLoader() -> CordovaBundleLoader {
        return CordovaBundleLoader(store: UserDefaultsStore(defaults: UserDefaults(suiteName: "CordovaBundleLoaderTests")!), startPage: "index.html", reloadStartPage: {})
    }

    // `ServedFile` is not Equatable, so files compare by path.
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
