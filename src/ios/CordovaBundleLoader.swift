import Cordova
import Foundation
import HotCodePushProtocol
import Network

/// Cordova serves the app from `www` in the binary through its scheme handler; the plugin answers that handler first,
/// so a bundle laid out by path under the store is served in its place, on the same origin.
final class CordovaBundleLoader: BundleLoader {
    static let embeddedDirectoryName = "www"

    static var storeDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("hotcodepush", isDirectory: true)
    }

    /// What `cordova prepare` adds to the app's own files: the bridge of the binary's plugins, never a bundle's.
    private static let frameworkFilePaths: Set<String> = ["/cordova.js", "/cordova_plugins.js"]
    private static let frameworkPathPrefixes = ["/plugins/", "/_app_file_"]
    private static let persistedBundleKey = "hotcodepush.cordova.servedBundleId"

    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private weak var viewController: CDVViewController?
    private var isMetered = false
    private var runningBundleId: String?

    init(viewController: CDVViewController?) {
        self.viewController = viewController
        runningBundleId = persistedBundleId()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isMetered = path.isExpensive || path.isConstrained
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func projectionDirectory(bundleId: String) -> URL {
        return CordovaBundleLoader.storeDirectory.appendingPathComponent("www", isDirectory: true).appendingPathComponent(bundleId, isDirectory: true)
    }

    func deleteProjection(bundleId: String) {
        try? FileManager.default.removeItem(at: projectionDirectory(bundleId: bundleId))
    }

    func persistServedBundle(bundleId: String?) {
        UserDefaults.standard.set(bundleId, forKey: CordovaBundleLoader.persistedBundleKey)
    }

    func loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId: bundleId)
        DispatchQueue.main.async { [weak self] in
            self?.setRunningBundleId(bundleId)
            self?.viewController?.loadStartPage()
        }
    }

    func servedBundleId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return runningBundleId
    }

    func isConnectionMetered() -> Bool {
        return isMetered
    }

    /// The file a request for the app's own path is answered with while a bundle runs; `nil` leaves the request to Cordova,
    /// which is every request under the embedded bundle and the framework's own files under any.
    func servedFile(forRequestPath path: String) -> ServedFile? {
        guard let bundleId = servedBundleId(), !CordovaBundleLoader.isFrameworkPath(path) else {
            return nil
        }
        let directory = projectionDirectory(bundleId: bundleId).standardizedFileURL
        let isStartPageRequest = path.isEmpty || (path as NSString).pathExtension.isEmpty
        let relativePath = isStartPageRequest ? (viewController?.startPage ?? "index.html") : path
        let fileURL = directory.appendingPathComponent(relativePath).standardizedFileURL
        // An encoded slash survives the web view's own normalization, so a path may still climb out of the bundle's directory.
        return fileURL.path.hasPrefix(directory.path + "/") ? .file(fileURL) : .missing
    }

    private static func isFrameworkPath(_ path: String) -> Bool {
        return frameworkFilePaths.contains(path) || frameworkPathPrefixes.contains(where: path.hasPrefix)
    }

    /// The bundle the last run left to serve, as long as its directory is still there.
    private func persistedBundleId() -> String? {
        guard let bundleId = UserDefaults.standard.string(forKey: CordovaBundleLoader.persistedBundleKey), FileManager.default.fileExists(atPath: projectionDirectory(bundleId: bundleId).path) else {
            return nil
        }
        return bundleId
    }

    private func setRunningBundleId(_ bundleId: String?) {
        lock.lock()
        defer { lock.unlock() }
        runningBundleId = bundleId
    }
}

/// What a running bundle answers a request with: one of its files, or nothing, which the web view sees as not found.
enum ServedFile {
    case file(URL)
    case missing
}

/// The files compiled into the binary, `www/` in the app bundle, addressed by the embedded manifest's hashes.
final class AppBundleEmbeddedBundle: EmbeddedBundle {
    private let pathsBySha256: [String: String]
    private let embeddedDirectory = Bundle.main.bundleURL.appendingPathComponent(CordovaBundleLoader.embeddedDirectoryName, isDirectory: true)

    init(manifest: EmbeddedBundleManifest) {
        var paths: [String: String] = [:]
        for file in manifest.files {
            paths[file.sha256] = file.path
        }
        pathsBySha256 = paths
    }

    func has(sha256: String) -> Bool {
        guard let path = pathsBySha256[sha256] else { return false }
        return FileManager.default.fileExists(atPath: embeddedDirectory.appendingPathComponent(path).path)
    }

    func copyFile(sha256: String, to destination: URL) throws {
        guard let path = pathsBySha256[sha256] else { throw PlainError("No embedded file with hash \(sha256)") }
        try FileManager.default.copyItem(at: embeddedDirectory.appendingPathComponent(path), to: destination)
    }
}
