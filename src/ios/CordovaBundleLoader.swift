import Foundation
import HotCodePushCore
import Network

/// Cordova serves the app from `www` in the binary through its scheme handler; the plugin answers that handler first,
/// so a bundle laid out by path under the store is served in its place, on the same origin.
/// Until the start has decided, nothing is served and nothing reloads: the bundle the core loads is only recorded.
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
    private let reloadStartPage: () -> Void
    private let startPage: String
    private let store: KeyValueStore
    private var isMetered = false
    private var isServing = false
    private var runningBundleId: String?

    /// The store is the core's own, so the bundle to serve at the next start lies beside the state it belongs to.
    /// `reloadStartPage` runs on the main thread.
    init(store: KeyValueStore, startPage: String, reloadStartPage: @escaping () -> Void) {
        self.store = store
        self.startPage = startPage
        self.reloadStartPage = reloadStartPage
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setIsMetered(path.isExpensive || path.isConstrained)
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// The start has decided: the page Cordova loads next is served from this bundle, `nil` for the embedded one,
    /// and every bundle the core loads from now on reloads the page.
    func beginServing(bundleId: String?) {
        lock.lock()
        defer { lock.unlock() }
        runningBundleId = bundleId
        isServing = true
    }

    func projectionDirectory(bundleId: String) -> URL {
        return CordovaBundleLoader.storeDirectory.appendingPathComponent("www", isDirectory: true).appendingPathComponent(bundleId, isDirectory: true)
    }

    func deleteProjection(bundleId: String) {
        try? FileManager.default.removeItem(at: projectionDirectory(bundleId: bundleId))
    }

    func persistServedBundle(bundleId: String?) {
        store.set(bundleId, forKey: CordovaBundleLoader.persistedBundleKey)
    }

    /// Before the start has decided, the bundle is persisted for the page about to load; once a page is served, it reloads.
    func loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId: bundleId)
        lock.lock()
        let isReloadNeeded = isServing
        lock.unlock()
        guard isReloadNeeded else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setRunningBundleId(bundleId)
            self?.reloadStartPage()
        }
    }

    /// Before the start has decided, the bundle persisted to serve, which the start adopts when it is the one waiting.
    func servedBundleId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return isServing ? runningBundleId : persistedBundleId()
    }

    func isConnectionMetered() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isMetered
    }

    /// The file a request for the app's own path is answered with while a bundle runs; `nil` leaves the request to Cordova,
    /// which is every request under the embedded bundle and the framework's own files under any.
    func servedFile(forRequestPath path: String) -> ServedFile? {
        guard let bundleId = readRunningBundleId(), !CordovaBundleLoader.isFrameworkPath(path) else {
            return nil
        }
        let directory = projectionDirectory(bundleId: bundleId).standardizedFileURL
        let isStartPageRequest = path.isEmpty || (path as NSString).pathExtension.isEmpty
        let relativePath = isStartPageRequest ? startPage : path
        let fileURL = directory.appendingPathComponent(relativePath).standardizedFileURL
        // An encoded slash survives the web view's own normalization, so a path may still climb out of the bundle's directory.
        return fileURL.path.hasPrefix(directory.path + "/") ? .file(fileURL) : .missing
    }

    private static func isFrameworkPath(_ path: String) -> Bool {
        return frameworkFilePaths.contains(path) || frameworkPathPrefixes.contains(where: path.hasPrefix)
    }

    /// The bundle the last run left to serve, as long as its directory is still there.
    private func persistedBundleId() -> String? {
        guard let bundleId = store.string(forKey: CordovaBundleLoader.persistedBundleKey), FileManager.default.fileExists(atPath: projectionDirectory(bundleId: bundleId).path) else {
            return nil
        }
        return bundleId
    }

    /// The bundle the page is served from, `nil` for the embedded one and before the start has decided.
    private func readRunningBundleId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return runningBundleId
    }

    private func setIsMetered(_ isMetered: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.isMetered = isMetered
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

    init(manifest: EmbeddedBundleManifest?) {
        var paths: [String: String] = [:]
        for file in manifest?.files ?? [] {
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
