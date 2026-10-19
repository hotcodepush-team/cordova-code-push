import Cordova
import Foundation
import HotCodePushCore
import WebKit

/// The Cordova bridge over the shared core: every action is one call into the core, every answer one JSON object.
@objc(HotCodePushPlugin)
public final class HotCodePushPlugin: CDVPlugin, CDVPluginSchemeHandler {
    private static let retainedEventName = "updateRolledBack"

    private let responder = ServedFileResponder()
    private var core: Core?
    private var eventCallbackId: String?
    private var loader: CordovaBundleLoader?
    /// What every call rejects with while there is no core: the resource file is missing, or the core's reader refused it.
    private var notConfiguredMessage = Configuration.missingMessage
    private var retainedEvent: [String: Any]?

    /// Cordova calls it in `viewDidLoad` and loads the start page right after, so the start decides first which bundle that page comes from.
    override public func pluginInitialize() {
        let configuration: Configuration?
        do {
            configuration = try Configuration.read(subdirectory: CordovaBundleLoader.embeddedDirectoryName)
        } catch {
            notConfiguredMessage = Configuration.resolveRefusedMessage(error)
            configuration = nil
        }
        guard let configuration = configuration else {
            NSLog("[HotCodePush] %@", notConfiguredMessage)
            return
        }
        let loader = CordovaBundleLoader(store: UserDefaultsStore(), startPage: viewController?.startPage ?? "index.html") { [weak self] in
            self?.reloadStartPage()
        }
        let core = Core(
            configuration: configuration,
            device: DeviceFacts.current(sdkVersion: sdkVersion),
            embedded: AppBundleEmbeddedBundle(manifest: configuration.embeddedBundleManifest, rootDirectory: CordovaBundleLoader.embeddedDirectory),
            loader: loader,
            listener: self)
        self.loader = loader
        self.core = core
        core.observeAppLifecycle()
        loader.beginServing(bundleId: core.handleAppStartBlocking())
    }

    /// A page started: the callback the events went to belongs to the page that is gone. A page the SDK did not load —
    /// `location.reload()`, a navigation, the recovery from a web content crash — is not reported to the core: what runs
    /// and when it is gated is the process start's.
    override public func onReset() {
        eventCallbackId = nil
    }

    /// The SDK's own reload, on the main thread: the departing page loses its callback first, so an event the core sends
    /// with the reload, a rollback's above all, is kept for the page that follows.
    private func reloadStartPage() {
        eventCallbackId = nil
        viewController?.loadStartPage()
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
        run(command) { core in try Json.encodeObject(await core.applyUpdate()) }
    }

    @objc(checkForUpdate:) func checkForUpdate(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.checkForUpdate()) }
    }

    @objc(clearUpdates:) func clearUpdates(_ command: CDVInvokedUrlCommand) {
        run(command) { core in
            await core.clearUpdates()
            return nil
        }
    }

    @objc(downloadUpdate:) func downloadUpdate(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.downloadUpdate(options: HotCodePushPlugin.downloadUpdateOptions(from: HotCodePushPlugin.options(of: command)))) }
    }

    @objc(getChannel:) func getChannel(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.channel()) }
    }

    @objc(getDevice:) func getDevice(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.deviceResult()) }
    }

    @objc(getState:) func getState(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.getState()) }
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
        run(command) { core in try Json.encodeObject(await core.notifyReady()) }
    }

    @objc(notifyRendered:) func notifyRendered(_ command: CDVInvokedUrlCommand) {
        run(command) { core in
            await core.handleRendered()
            return nil
        }
    }

    @objc(rollbackUpdate:) func rollbackUpdate(_ command: CDVInvokedUrlCommand) {
        let reason = HotCodePushPlugin.options(of: command)["reason"] as? String
        run(command) { core in
            try await core.rollbackUpdate(detail: reason)
            return nil
        }
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
        run(command) { core in
            try await core.setAttributes(changes)
            return nil
        }
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
        run(command) { core in
            try await core.setChannel(choice)
            return nil
        }
    }

    @objc(setRestartAllowed:) func setRestartAllowed(_ command: CDVInvokedUrlCommand) {
        run(command) { core in
            guard let isAllowed = HotCodePushPlugin.options(of: command)["isAllowed"] as? Bool else { throw PlainError("isAllowed must be a boolean") }
            await core.setRestartAllowed(isAllowed)
            return nil
        }
    }

    @objc(showDebugScreen:) func showDebugScreen(_ command: CDVInvokedUrlCommand) {
        guard let core = core, let viewController = viewController else {
            reject(command, notConfiguredMessage)
            return
        }
        DispatchQueue.main.async {
            DebugScreenViewController.present(core: core, from: viewController)
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command.callbackId)
        }
    }

    @objc(sync:) func sync(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.sync(trigger: .manual, options: HotCodePushPlugin.syncOptions(from: HotCodePushPlugin.options(of: command)))) }
    }

    // MARK: The bridge

    /// The one options object every method takes, empty when the web layer passed none.
    private static func options(of command: CDVInvokedUrlCommand) -> [String: Any] {
        return command.argument(at: 0) as? [String: Any] ?? [:]
    }

    /// Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call.
    private static func syncOptions(from options: [String: Any]) throws -> SyncOptions {
        return SyncOptions(
            applyStrategy: try option("applyStrategy", options, ApplyStrategy.init(rawValue:)),
            downloadStrategy: try option("downloadStrategy", options, DownloadStrategy.init(rawValue:)),
            mandatoryApplyStrategy: try option("mandatoryApplyStrategy", options, MandatoryApplyStrategy.init(rawValue:)))
    }

    /// The apply strategies for this call; the download strategy is pinned to `auto`.
    private static func downloadUpdateOptions(from options: [String: Any]) throws -> DownloadUpdateOptions {
        return DownloadUpdateOptions(
            applyStrategy: try option("applyStrategy", options, ApplyStrategy.init(rawValue:)),
            mandatoryApplyStrategy: try option("mandatoryApplyStrategy", options, MandatoryApplyStrategy.init(rawValue:)))
    }

    private static func option<T>(_ name: String, _ options: [String: Any], _ parse: (String) -> T?) throws -> T? {
        guard let raw = options[name] as? String else { return nil }
        guard let value = parse(raw) else { throw PlainError("\(name) is not one of its choices: \(raw)") }
        return value
    }

    /// Answers the body's result, or an empty success when an action that returns nothing ends its body in `nil`.
    private func run(_ command: CDVInvokedUrlCommand, _ body: @escaping (Core) async throws -> [String: Any]?) {
        guard let core = core else {
            reject(command, notConfiguredMessage)
            return
        }
        Task {
            do {
                let result = try await body(core).map { CDVPluginResult(status: .ok, messageAs: $0) } ?? CDVPluginResult(status: .ok)
                commandDelegate.send(result, callbackId: command.callbackId)
            } catch {
                reject(command, error.localizedDescription)
            }
        }
    }

    private func reject(_ command: CDVInvokedUrlCommand, _ message: String) {
        commandDelegate.send(CDVPluginResult(status: .error, messageAs: message), callbackId: command.callbackId)
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

    public func downloadProgress(_ event: DownloadProgressEvent) {
        notify("downloadProgress", event)
    }

    public func updateRolledBack(_ event: UpdateRolledBackEvent) {
        notify(HotCodePushPlugin.retainedEventName, event)
    }

    private func notify<T: Encodable>(_ eventName: String, _ event: T) {
        guard let data = try? Json.encodeObject(event) else { return }
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
