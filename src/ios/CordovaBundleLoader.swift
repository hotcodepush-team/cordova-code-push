import Foundation
import HotCodePushCore

/// Cordova serves the app from `www` in the binary through its scheme handler; the plugin answers that handler first,
/// so a bundle laid out by path under the store is served in its place, on the same origin.
/// Until the start has decided, nothing is served and nothing reloads: the bundle the core loads is only recorded.
final class CordovaBundleLoader: BundleLoader {
    static let embeddedDirectoryName = "www"
    static let embeddedDirectory = Bundle.main.bundleURL.appendingPathComponent(embeddedDirectoryName, isDirectory: true)

    /// What `cordova prepare` adds to the app's own files: the bridge of the binary's plugins, never a bundle's.
    private static let frameworkFilePaths: Set<String> = ["/cordova.js", "/cordova_plugins.js"]
    private static let frameworkPathPrefixes = ["/plugins/", "/_app_file_"]
    private static let persistedBundleKey = "hotcodepush.cordova.servedBundleId"

    private let lock = NSLock()
    private let networkMonitor = NetworkMonitor()
    private let reloadStartPage: () -> Void
    private let startPage: String
    private let store: KeyValueStore
    private var isServing = false
    private var runningBundleId: String?

    /// The store is the core's own, so the bundle to serve at the next start lies beside the state it belongs to.
    /// `reloadStartPage` runs on the main thread.
    init(store: KeyValueStore, startPage: String, reloadStartPage: @escaping () -> Void) {
        self.store = store
        self.startPage = startPage
        self.reloadStartPage = reloadStartPage
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
        return FileStore.defaultRootDirectory.appendingPathComponent("www", isDirectory: true).appendingPathComponent(bundleId, isDirectory: true)
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
        return networkMonitor.isConnectionMetered()
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
