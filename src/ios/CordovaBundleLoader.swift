import Foundation
import HotCodePushCore

// The plugin answers Cordova's scheme handler first, so a bundle is served in place of the binary's `www` on the same origin.
// Until the start decides, nothing is served or reloaded.
final class CordovaBundleLoader: BundleLoader {
    static let embeddedDirectoryName = "www"
    static let embeddedDirectory = Bundle.main.bundleURL.appendingPathComponent(embeddedDirectoryName, isDirectory: true)

    // `cordova prepare` writes these files for the binary's plugins, so a bundle never serves them.
    private static let frameworkFilePaths: Set<String> = ["/cordova.js", "/cordova_plugins.js"]
    private static let frameworkPathPrefixes = ["/plugins/", "/_app_file_"]
    private static let persistedBundleKey = "hotcodepush.servedBundleId"

    private let lock = NSLock()
    private let reloadStartPage: () -> Void
    private let startPage: String
    private let store: KeyValueStore
    private var isServing = false
    private var runningBundleId: String?

    // The core's own store, so the served bundle is kept beside the state it belongs to.
    // `reloadStartPage` runs on the main thread.
    init(store: KeyValueStore, startPage: String, reloadStartPage: @escaping () -> Void) {
        self.store = store
        self.startPage = startPage
        self.reloadStartPage = reloadStartPage
    }

    // `nil` serves the embedded bundle. From now on, every bundle the core loads reloads the page.
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

    func servedBundleId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return isServing ? runningBundleId : persistedBundleId()
    }

    // `nil` leaves the request to Cordova: under the embedded bundle, and for the framework files under any bundle.
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

    private func persistedBundleId() -> String? {
        guard let bundleId = store.string(forKey: CordovaBundleLoader.persistedBundleKey), FileManager.default.fileExists(atPath: projectionDirectory(bundleId: bundleId).path) else {
            return nil
        }
        return bundleId
    }

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

// The web view sees `missing` as not found.
enum ServedFile {
    case file(URL)
    case missing
}
