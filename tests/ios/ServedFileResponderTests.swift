import WebKit
import XCTest
@testable import HotCodePushCordova

/// `ServedFileResponder.respond(to:with:)`: the status, the headers and the bytes a scheme task receives for a served file,
/// with or without a `Range` header, and nothing after the web view stops the task.
final class ServedFileResponderTests: XCTestCase {
    private let responder = ServedFileResponder()
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hotcodepush-cordova-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testShouldAnswerTheWholeFileWithItsTypeAndNoCachingWhenNoRangeIsAsked() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file))

        XCTAssertEqual(task.response?.statusCode, 200)
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Length"), "10")
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(task.receivedData, Data("0123456789".utf8))
    }

    func testShouldAnswerTheAskedBytesWithPartialContentWhenARangeIsAsked() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file), range: "bytes=2-5")

        XCTAssertEqual(task.response?.statusCode, 206)
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Range"), "bytes 2-5/10")
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Length"), "4")
        XCTAssertEqual(task.receivedData, Data("2345".utf8))
    }

    func testShouldAnswerUpToTheLastByteWhenTheRangeHasNoEnd() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file), range: "bytes=4-")

        XCTAssertEqual(task.response?.statusCode, 206)
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Range"), "bytes 4-9/10")
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Length"), "6")
        XCTAssertEqual(task.receivedData, Data("456789".utf8))
    }

    func testShouldAnswerUpToTheLastByteWhenTheRangeEndsPastTheFile() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file), range: "bytes=2-1000")

        XCTAssertEqual(task.response?.statusCode, 206)
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Range"), "bytes 2-9/10")
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Length"), "8")
        XCTAssertEqual(task.receivedData, Data("23456789".utf8))
    }

    func testShouldAnswerTheWholeFileWhenTheRangeIsASuffix() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file), range: "bytes=-3")

        XCTAssertEqual(task.response?.statusCode, 200)
        XCTAssertNil(task.response?.value(forHTTPHeaderField: "Content-Range"))
        XCTAssertEqual(task.receivedData, Data("0123456789".utf8))
    }

    func testShouldAnswerTheWholeFileWhenTheRangeHasNoBytesUnit() throws {
        let file = try writeFile("app.js", contents: "0123456789")

        let task = respond(with: .file(file), range: "2-5")

        XCTAssertEqual(task.response?.statusCode, 200)
        XCTAssertNil(task.response?.value(forHTTPHeaderField: "Content-Range"))
        XCTAssertEqual(task.receivedData, Data("0123456789".utf8))
    }

    func testShouldAnswerRangeNotSatisfiableWhenAnEmptyFileIsAskedFromItsFirstByte() throws {
        let file = try writeFile("app.js", contents: "")

        let task = respond(with: .file(file), range: "bytes=0-")

        XCTAssertEqual(task.response?.statusCode, 416)
        XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Range"), "bytes */0")
        XCTAssertTrue(task.receivedData.isEmpty)
    }

    func testShouldAnswerNotFoundWhenTheBundleHasNoFile() {
        let task = respond(with: .missing)

        XCTAssertEqual(task.response?.statusCode, 404)
        XCTAssertTrue(task.receivedData.isEmpty)
    }

    func testShouldAnswerNotFoundWhenTheFileDoesNotExist() {
        let file = directory.appendingPathComponent("app.js")

        let task = respond(with: .file(file))

        XCTAssertEqual(task.response?.statusCode, 404)
        XCTAssertTrue(task.receivedData.isEmpty)
    }

    func testShouldSendNoDataAndNoFinishWhenTheTaskIsStopped() throws {
        let file = try writeFile("app.js", contents: "0123456789")
        let task = FakeSchemeTask(request: request())
        task.ended.isInverted = true

        responder.respond(to: task, with: .file(file))
        responder.stop(task)

        wait(for: [task.ended], timeout: 0.5)
        XCTAssertTrue(task.receivedData.isEmpty)
    }

    /// Waits for the finish: the body is read on a background queue and handed to the task on the main queue.
    private func respond(with servedFile: ServedFile, range: String? = nil) -> FakeSchemeTask {
        let task = FakeSchemeTask(request: request(range: range))
        responder.respond(to: task, with: servedFile)
        wait(for: [task.ended], timeout: 5)
        return task
    }

    private func request(range: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "app://localhost/app.js")!)
        request.setValue(range, forHTTPHeaderField: "Range")
        return request
    }

    private func writeFile(_ name: String, contents: String) throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }
}

/// Records what the responder sends; `ended` is fulfilled when the task finishes or fails.
private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
    let ended = XCTestExpectation(description: "the task finishes or fails")
    let request: URLRequest
    private(set) var receivedData = Data()
    private(set) var response: HTTPURLResponse?

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {
        self.response = response as? HTTPURLResponse
    }

    func didReceive(_ data: Data) {
        receivedData.append(data)
    }

    func didFinish() {
        ended.fulfill()
    }

    func didFailWithError(_ error: Error) {
        ended.fulfill()
    }
}
