import WebKit
import XCTest
@testable import HotCodePushCordova

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

    // A 416 answer carries no body and so no Content-Length.
    func testShouldAnswerEachRangeWithItsStatusAndBytes() throws {
        let cases: [(range: String, contents: String, status: Int, contentRange: String?, body: String)] = [
            ("bytes=2-5", "0123456789", 206, "bytes 2-5/10", "2345"),
            ("bytes=4-", "0123456789", 206, "bytes 4-9/10", "456789"),
            ("bytes=2-1000", "0123456789", 206, "bytes 2-9/10", "23456789"),
            ("bytes=-3", "0123456789", 206, "bytes 7-9/10", "789"),
            ("bytes=-20", "0123456789", 206, "bytes 0-9/10", "0123456789"),
            ("bytes=-3", "", 200, nil, ""),
            ("bytes=0-1,5-6", "0123456789", 200, nil, "0123456789"),
            ("2-5", "0123456789", 200, nil, "0123456789"),
            ("bytes=two-five", "0123456789", 200, nil, "0123456789"),
            ("bytes=0-", "", 416, "bytes */0", ""),
            ("bytes=10-", "0123456789", 416, "bytes */10", ""),
            ("bytes=100-200", "0123456789", 416, "bytes */10", ""),
            ("bytes=5-2", "0123456789", 416, "bytes */10", ""),
            ("bytes=-0", "0123456789", 416, "bytes */10", "")
        ]
        for testCase in cases {
            let file = try writeFile("app.js", contents: testCase.contents)

            let task = respond(with: .file(file), range: testCase.range)

            let message = "\(testCase.range) of \(testCase.contents.count) bytes"
            XCTAssertEqual(task.response?.statusCode, testCase.status, message)
            XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Range"), testCase.contentRange, message)
            XCTAssertEqual(task.response?.value(forHTTPHeaderField: "Content-Length"), testCase.status == 416 ? nil : String(testCase.body.count), message)
            XCTAssertEqual(task.receivedData, Data(testCase.body.utf8), message)
        }
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

    func testShouldThrowWhenAChunkCannotBeRead() throws {
        let file = try writeFile("app.js", contents: "0123456789")
        let writeOnlyHandle = try FileHandle(forWritingTo: file)

        XCTAssertThrowsError(try ServedFileResponder.readChunk(of: writeOnlyHandle, upToCount: 4))
    }

    // The body is read on a background queue and handed to the task on the main queue, so this waits for the end.
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
