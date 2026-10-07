import Cordova
import Foundation
import HotCodePushCore
import UIKit
import WebKit

/// The Cordova bridge over the shared core: every action is one call into the core, every answer one JSON object.
@objc(HotCodePushPlugin)
public final class HotCodePushPlugin: CDVPlugin, CDVPluginSchemeHandler {
    public static let sdkVersion = "0.0.0"

    private static let notConfiguredMessage = "HotCodePush is not configured: hotcodepush.json is missing from the app's resources. Run `npx hotcodepush init` and build the app once."
    private static let retainedEventName = "rolledBack"

    private let responder = ServedFileResponder()
    private var core: Core?
    private var eventCallbackId: String?
    private var loader: CordovaBundleLoader?
    private var retainedEvent: [String: Any]?

    /// Cordova calls it in `viewDidLoad` and loads the start page right after, so the start decides first which bundle that page comes from.
    override public func pluginInitialize() {
        guard let configuration = HotCodePushPlugin.readConfiguration() else {
            NSLog("[HotCodePush] %@", HotCodePushPlugin.notConfiguredMessage)
            return
        }
        let store = UserDefaultsStore()
        let loader = CordovaBundleLoader(store: store, startPage: viewController?.startPage ?? "index.html") { [weak self] in
            self?.reloadStartPage()
        }
        let core = Core(
            configuration: configuration,
            device: HotCodePushPlugin.deviceFacts(),
            store: store,
            files: FileStore(rootDirectory: CordovaBundleLoader.storeDirectory),
            embedded: AppBundleEmbeddedBundle(manifest: configuration.embeddedBundleManifest),
            http: UrlSessionHttpClient(),
            loader: loader,
            listener: self)
        self.loader = loader
        self.core = core
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        loader.beginServing(bundleId: core.handleAppStartBlocking())
    }

    /// The page left: the callback the events went to belongs to the page that is gone.
    override public func onReset() {
        eventCallbackId = nil
    }

    private func reloadStartPage() {
        viewController?.loadStartPage()
    }

    @objc private func handleDidEnterBackground() {
        Task { await core?.handleAppPause() }
    }

    @objc private func handleWillEnterForeground() {
        Task { await core?.handleAppResume() }
    }

    // MARK: The served bundle

    /// A request for the running bundle's own files is answered from its directory; Cordova answers the rest from the binary.
    public func overrideSchemeTask(_ task: WKURLSchemeTask) -> Bool {
        guard let url = task.request.url, let servedFile = loader?.servedFile(forRequestPath: url.path) else {
            return false
        }
        responder.respond(to: task, with: servedFile)
        return true
    }

    public func stop(_ task: WKURLSchemeTask) {
        responder.stop(task)
    }

    // MARK: Actions

    @objc(applyUpdate:) func applyUpdate(_ command: CDVInvokedUrlCommand) {
        run(command) { core in await core.applyUpdate() }
    }

    @objc(checkForUpdate:) func checkForUpdate(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try await core.checkForUpdate() }
    }

    @objc(clearUpdates:) func clearUpdates(_ command: CDVInvokedUrlCommand) {
        runVoid(command) { core in await core.clearUpdates() }
    }

    @objc(downloadUpdate:) func downloadUpdate(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try await core.downloadUpdate() }
    }

    @objc(getChannel:) func getChannel(_ command: CDVInvokedUrlCommand) {
        run(command) { core in await core.channel() }
    }

    @objc(getDevice:) func getDevice(_ command: CDVInvokedUrlCommand) {
        run(command) { core in await core.deviceResult() }
    }

    @objc(getState:) func getState(_ command: CDVInvokedUrlCommand) {
        run(command) { core in await core.getState() }
    }

    /// The one callback the web layer registers for the life of the page; every event is answered on it.
    @objc(listen:) func listen(_ command: CDVInvokedUrlCommand) {
        eventCallbackId = command.callbackId
        if let retainedEvent = retainedEvent {
            send(event: retainedEvent)
            self.retainedEvent = nil
        }
    }

    @objc(notifyReady:) func notifyReady(_ command: CDVInvokedUrlCommand) {
        run(command) { core in await core.notifyReady() }
    }

    @objc(notifyRendered:) func notifyRendered(_ command: CDVInvokedUrlCommand) {
        runVoid(command) { core in await core.handleRendered() }
    }

    @objc(rollbackUpdate:) func rollbackUpdate(_ command: CDVInvokedUrlCommand) {
        let reason = HotCodePushPlugin.options(of: command)["reason"] as? String
        runVoid(command) { core in try await core.rollbackUpdate(detail: reason) }
    }

    @objc(setAttributes:) func setAttributes(_ command: CDVInvokedUrlCommand) {
        var changes: [String: String?] = [:]
        for (key, value) in HotCodePushPlugin.options(of: command) {
            if value is NSNull {
                changes[key] = .some(nil)
            } else if let value = value as? String {
                changes[key] = value
            } else {
                reject(command, "An attribute value is a string or null: \(key)")
                return
            }
        }
        runVoid(command) { core in try await core.setAttributes(changes) }
    }

    @objc(setChannel:) func setChannel(_ command: CDVInvokedUrlCommand) {
        let options = HotCodePushPlugin.options(of: command)
        let choice: ChannelChoice?
        if let id = options["id"] as? String {
            choice = .id(id)
        } else if let name = options["name"] as? String {
            choice = .name(name)
        } else {
            choice = nil
        }
        runVoid(command) { core in try await core.setChannel(choice) }
    }

    @objc(setRestartAllowed:) func setRestartAllowed(_ command: CDVInvokedUrlCommand) {
        guard let allowed = HotCodePushPlugin.options(of: command)["allowed"] as? Bool else {
            reject(command, "allowed must be a boolean")
            return
        }
        runVoid(command) { core in await core.setRestartAllowed(allowed) }
    }

    @objc(showDebugScreen:) func showDebugScreen(_ command: CDVInvokedUrlCommand) {
        guard let core = core, let viewController = viewController else {
            reject(command, HotCodePushPlugin.notConfiguredMessage)
            return
        }
        DispatchQueue.main.async {
            DebugScreenViewController.present(core: core, from: viewController)
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command.callbackId)
        }
    }

    @objc(sync:) func sync(_ command: CDVInvokedUrlCommand) {
        do {
            let options = try HotCodePushPlugin.syncOptions(from: HotCodePushPlugin.options(of: command))
            run(command) { core in try await core.sync(trigger: .manual, options: options) }
        } catch {
            reject(command, error.localizedDescription)
        }
    }

    // MARK: The bridge

    /// The one options object every method takes, empty when the web layer passed none.
    private static func options(of command: CDVInvokedUrlCommand) -> [String: Any] {
        return command.argument(at: 0) as? [String: Any] ?? [:]
    }

    /// Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call.
    private static func syncOptions(from options: [String: Any]) throws -> SyncOptions {
        return SyncOptions(
            downloadStrategy: try option("downloadStrategy", options, DownloadStrategy.init(rawValue:)),
            installStrategy: try option("installStrategy", options, InstallStrategy.init(rawValue:)),
            mandatoryInstallStrategy: try option("mandatoryInstallStrategy", options, MandatoryInstallStrategy.init(rawValue:)))
    }

    private static func option<T>(_ name: String, _ options: [String: Any], _ parse: (String) -> T?) throws -> T? {
        guard let raw = options[name] as? String else { return nil }
        guard let value = parse(raw) else { throw PlainError("\(name) is not one of its choices: \(raw)") }
        return value
    }

    private func run<T: Encodable>(_ command: CDVInvokedUrlCommand, _ body: @escaping (Core) async throws -> T) {
        guard let core = core else {
            reject(command, HotCodePushPlugin.notConfiguredMessage)
            return
        }
        Task {
            do {
                let result = CDVPluginResult(status: .ok, messageAs: try HotCodePushPlugin.jsonObject(try await body(core)))
                commandDelegate.send(result, callbackId: command.callbackId)
            } catch {
                reject(command, error.localizedDescription)
            }
        }
    }

    private func runVoid(_ command: CDVInvokedUrlCommand, _ body: @escaping (Core) async throws -> Void) {
        guard let core = core else {
            reject(command, HotCodePushPlugin.notConfiguredMessage)
            return
        }
        Task {
            do {
                try await body(core)
                commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command.callbackId)
            } catch {
                reject(command, error.localizedDescription)
            }
        }
    }

    private func reject(_ command: CDVInvokedUrlCommand, _ message: String) {
        commandDelegate.send(CDVPluginResult(status: .error, messageAs: message), callbackId: command.callbackId)
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try Json.encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlainError("The result could not be encoded")
        }
        return object
    }

    // MARK: The platform's facts

    private static func readConfiguration() -> Configuration? {
        guard let url = Bundle.main.url(forResource: "hotcodepush", withExtension: "json", subdirectory: CordovaBundleLoader.embeddedDirectoryName), let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try Configuration.decode(data)
        } catch {
            NSLog("[HotCodePush] hotcodepush.json could not be read: %@", String(describing: error))
            return nil
        }
    }

    private static func deviceFacts() -> DeviceFacts {
        let info = Bundle.main.infoDictionary ?? [:]
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return DeviceFacts(
            platform: "ios",
            binaryVersion: info["CFBundleShortVersionString"] as? String ?? "",
            binaryBuild: info["CFBundleVersion"] as? String ?? "",
            osVersion: UIDevice.current.systemVersion,
            sdkVersion: sdkVersion,
            isDebugBuild: isDebugBuild)
    }
}

extension HotCodePushPlugin: CoreListener {
    public func updateAvailable(_ event: UpdateAvailableEvent) {
        notify("updateAvailable", event)
    }

    public func updateDownloaded(_ event: UpdateDownloadedEvent) {
        notify("updateDownloaded", event)
    }

    public func updateFailed(_ event: UpdateFailedEvent) {
        notify("updateFailed", event)
    }

    public func downloadProgress(releaseId: String, downloadedBytes: Int, totalBytes: Int) {
        let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
        send(event: ["eventName": "downloadProgress", "data": ["releaseId": releaseId, "downloadedBytes": downloadedBytes, "totalBytes": totalBytes, "progress": progress]])
    }

    public func rolledBack(_ event: RolledBackEvent) {
        notify(HotCodePushPlugin.retainedEventName, event)
    }

    private func notify<T: Encodable>(_ eventName: String, _ event: T) {
        guard let data = try? HotCodePushPlugin.jsonObject(event) else { return }
        send(event: ["eventName": eventName, "data": data])
    }

    /// An event goes to the page's callback; a rollback is kept until the reloaded page listens, since it belongs to the start that follows it.
    private func send(event: [String: Any]) {
        DispatchQueue.main.async {
            guard let callbackId = self.eventCallbackId else {
                if event["eventName"] as? String == HotCodePushPlugin.retainedEventName {
                    self.retainedEvent = event
                }
                return
            }
            let result = CDVPluginResult(status: .ok, messageAs: event)
            result.setKeepCallbackAs(true)
            self.commandDelegate.send(result, callbackId: callbackId)
        }
    }
}
