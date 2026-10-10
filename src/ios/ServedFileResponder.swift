import Foundation
import MobileCoreServices
import UniformTypeIdentifiers
import WebKit

/// Answers a scheme task with a file the way Cordova's own handler answers from the binary: the type from the extension,
/// no caching, byte ranges for media, and nothing sent to a task the web view has stopped.
final class ServedFileResponder {
    private struct ByteRange {
        let offset: UInt64
        let length: Int
    }

    /// What a `Range` header asks of a file: the whole of it, a part of it, or a range the file cannot satisfy.
    private enum RequestedRange {
        case wholeFile
        case part(ByteRange)
        case unsatisfiable
    }

    private static let chunkSize = 4 * 1024 * 1024
    private static let fallbackMimeType = "application/octet-stream"
    /// The types the web layer loads strictly by, which the system's type table does not always know.
    private static let mimeTypesByExtension = ["js": "text/javascript", "mjs": "text/javascript", "wasm": "application/wasm"]

    /// The tasks still wanted, touched on the main thread only, where WebKit starts and stops them.
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

    /// Reads off the main thread and hands every chunk back on it, where a stop is seen before the next callback.
    private func send(_ range: ByteRange, of handle: FileHandle, to task: WKURLSchemeTask) {
        handle.seek(toFileOffset: range.offset)
        var remaining = range.length
        while remaining > 0 {
            let chunk = handle.readData(ofLength: min(remaining, ServedFileResponder.chunkSize))
            if chunk.isEmpty { break }
            remaining -= chunk.count
            DispatchQueue.main.async { [weak self] in
                guard self?.isActive(task) == true else { return }
                task.didReceive(chunk)
            }
        }
        handle.closeFile()
        DispatchQueue.main.async { [weak self] in
            guard self?.isActive(task) == true else { return }
            task.didFinish()
            self?.stop(task)
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
        if #available(iOS 14.0, *) {
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? fallbackMimeType
        }
        return (ServedFileResponder.self as LegacyMimeTypes.Type).legacyMimeType(forExtension: pathExtension) ?? fallbackMimeType
    }

    /// The range a `Range: bytes=` header asks per RFC 9110, `<start>-<end>`, `<start>-` or `-<length>`, clamped to the file.
    /// A range starting at or past the file's end, ending before its start, or of no bytes is unsatisfiable.
    /// The whole file answers a header that does not parse, several ranges rather than a multipart body,
    /// and a suffix of an empty file, which no `Content-Range` can express.
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

/// iOS 13 has no `UTType`; its type table is reached through the functions iOS 15 deprecates.
/// Called through the protocol, the deprecation stays here and out of every build of an app with a newer deployment target.
private protocol LegacyMimeTypes {
    static func legacyMimeType(forExtension pathExtension: String) -> String?
}

extension ServedFileResponder: LegacyMimeTypes {
    @available(iOS, deprecated: 14.0)
    fileprivate static func legacyMimeType(forExtension pathExtension: String) -> String? {
        guard let identifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue() else {
            return nil
        }
        return UTTypeCopyPreferredTagWithClass(identifier, kUTTagClassMIMEType)?.takeRetainedValue() as String?
    }
}
