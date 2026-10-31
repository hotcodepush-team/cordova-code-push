import Foundation
import UniformTypeIdentifiers
import WebKit

// Mirrors how Cordova's own scheme handler answers from the binary.
final class ServedFileResponder {
    private struct ByteRange {
        let offset: UInt64
        let length: Int
    }

    private enum RequestedRange {
        case wholeFile
        case part(ByteRange)
        case unsatisfiable
    }

    private static let chunkSize = 4 * 1024 * 1024
    private static let fallbackMimeType = "application/octet-stream"
    // The web layer checks these types strictly, and the system type table does not always know them.
    private static let mimeTypesByExtension = ["js": "text/javascript", "mjs": "text/javascript", "wasm": "application/wasm"]

    // Main thread only, where WebKit starts and stops the tasks.
    private var activeTasks = Set<ObjectIdentifier>()
    private let readQueue = DispatchQueue(label: "com.hotcodepush.cordova.served-files", qos: .userInitiated)

    func respond(to task: WKURLSchemeTask, with servedFile: ServedFile) {
        activeTasks.insert(ObjectIdentifier(task))
        guard case .file(let fileURL) = servedFile, let url = task.request.url, let fileSize = ServedFileResponder.fileSize(of: fileURL), let handle = try? FileHandle(forReadingFrom: fileURL) else {
            finish(task, status: 404, headers: [:])
            return
        }
        var headers = ["Cache-Control": "no-cache", "Content-Type": ServedFileResponder.mimeType(of: fileURL)]
        var range = ByteRange(offset: 0, length: fileSize)
        var status = 200
        switch ServedFileResponder.requestedRange(of: task.request, fileSize: fileSize) {
        case .wholeFile:
            break
        case .part(let requestedRange):
            range = requestedRange
            status = 206
            headers["Content-Range"] = "bytes \(range.offset)-\(range.offset + UInt64(range.length) - 1)/\(fileSize)"
        case .unsatisfiable:
            handle.closeFile()
            finish(task, status: 416, headers: ["Content-Range": "bytes */\(fileSize)"])
            return
        }
        headers["Content-Length"] = String(range.length)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            handle.closeFile()
            finish(task, status: 500, headers: [:])
            return
        }
        task.didReceive(response)
        readQueue.async { [weak self] in
            self?.send(range, of: handle, to: task)
        }
    }

    func stop(_ task: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(task))
    }

    // Chunks go back to the main thread, where a stop is seen before the next callback.
    // The response is already sent, so a failed read ends the task with its error, as in Cordova's own handler.
    private func send(_ range: ByteRange, of handle: FileHandle, to task: WKURLSchemeTask) {
        let result = Result { try sendChunks(range, of: handle, to: task) }
        handle.closeFile()
        DispatchQueue.main.async { [weak self] in
            guard self?.isActive(task) == true else { return }
            switch result {
            case .success:
                task.didFinish()
            case .failure(let error):
                task.didFailWithError(error)
            }
            self?.stop(task)
        }
    }

    private func sendChunks(_ range: ByteRange, of handle: FileHandle, to task: WKURLSchemeTask) throws {
        try handle.seek(toOffset: range.offset)
        var remaining = range.length
        while remaining > 0 {
            let chunk = try ServedFileResponder.readChunk(of: handle, upToCount: min(remaining, ServedFileResponder.chunkSize))
            if chunk.isEmpty { break }
            remaining -= chunk.count
            DispatchQueue.main.async { [weak self] in
                guard self?.isActive(task) == true else { return }
                task.didReceive(chunk)
            }
        }
    }

    private func finish(_ task: WKURLSchemeTask, status: Int, headers: [String: String]) {
        if let url = task.request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) {
            task.didReceive(response)
            task.didFinish()
        } else {
            task.didFailWithError(URLError(.fileDoesNotExist))
        }
        stop(task)
    }

    private func isActive(_ task: WKURLSchemeTask) -> Bool {
        return activeTasks.contains(ObjectIdentifier(task))
    }

    private static func fileSize(of fileURL: URL) -> Int? {
        return (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private static func mimeType(of fileURL: URL) -> String {
        let pathExtension = fileURL.pathExtension.lowercased()
        if let mimeType = mimeTypesByExtension[pathExtension] {
            return mimeType
        }
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? fallbackMimeType
    }

    static func readChunk(of handle: FileHandle, upToCount count: Int) throws -> Data {
        return try handle.read(upToCount: count) ?? Data()
    }

    // Parses `bytes=<start>-<end>`, `bytes=<start>-` and `bytes=-<length>` per RFC 9110, clamped to the file.
    // Unparsable headers and multiple ranges get the whole file, which avoids a multipart body.
    // An empty file's suffix range also gets the whole file, because no `Content-Range` can express it.
    private static func requestedRange(of request: URLRequest, fileSize: Int) -> RequestedRange {
        guard let header = request.value(forHTTPHeaderField: "Range"), header.hasPrefix("bytes="), !header.contains(",") else {
            return .wholeFile
        }
        let bounds = header.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else {
            return .wholeFile
        }
        let size = UInt64(fileSize)
        if bounds[0].isEmpty {
            guard let suffixLength = UInt64(bounds[1]) else {
                return .wholeFile
            }
            guard suffixLength > 0 else {
                return .unsatisfiable
            }
            guard size > 0 else {
                return .wholeFile
            }
            let length = min(suffixLength, size)
            return .part(ByteRange(offset: size - length, length: Int(length)))
        }
        guard let start = UInt64(bounds[0]), let end = bounds[1].isEmpty ? UInt64.max : UInt64(bounds[1]) else {
            return .wholeFile
        }
        guard start < size, start <= end else {
            return .unsatisfiable
        }
        return .part(ByteRange(offset: start, length: Int(min(end, size - 1) - start + 1)))
    }
}
