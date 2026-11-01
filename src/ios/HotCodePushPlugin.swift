import Cordova
import Foundation
import HotCodePushCore
import WebKit

// The core ships as a prebuilt Release build. The SDK compiles with the app, so it reads the debug flag here.
#if DEBUG
private let isDebugBuild = true
#else
private let isDebugBuild = false
#endif

@objc(HotCodePushPlugin)
public final class HotCodePushPlugin: CDVPlugin, CDVPluginSchemeHandler {
    private static let retainedEventName = "updateRolledBack"

    private let responder = ServedFileResponder()
    private var core: Core?
    private var eventCallbackId: String?
    private var loader: CordovaBundleLoader?
    private var notConfiguredMessage = Configuration.missingMessage
    private var retainedEvent: [String: Any]?

    // Cordova calls this in `viewDidLoad` and loads the start page right after, so the start decides first which bundle serves it.
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
            device: DeviceFacts.current(sdkVersion: sdkVersion, isDebugBuild: isDebugBuild),
            embedded: AppBundleEmbeddedBundle(manifest: configuration.embeddedBundleManifest, rootDirectory: CordovaBundleLoader.embeddedDirectory),
            loader: loader,
            listener: self)
        self.loader = loader
        self.core = core
        core.observeAppLifecycle()
        loader.beginServing(bundleId: core.handleAppStartBlocking())
    }

    // A page start the SDK did not request, such as `location.reload()` or a web content crash recovery, is not reported to the core.
    // The process start alone decides what runs and gates it.
    override public func onReset() {
        eventCallbackId = nil
    }

    // Runs on the main thread. The departing page loses its callback first,
    // so an event sent with the reload, above all a rollback, waits for the next page.
    private func reloadStartPage() {
        eventCallbackId = nil
        viewController?.loadStartPage()
    }

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
        run(command) { core in try Json.encodeObject(await core.getChannel()) }
    }

    @objc(getDevice:) func getDevice(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.getDevice()) }
    }

    @objc(getState:) func getState(_ command: CDVInvokedUrlCommand) {
        run(command) { core in try Json.encodeObject(await core.getState()) }
    }

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
        guard let core = core else {
            reject(command, notConfiguredMessage)
            return
        }
        guard let viewController = viewController else {
            reject(command, "The debug screen has no view controller to open over")
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

    private static func options(of command: CDVInvokedUrlCommand) -> [String: Any] {
        return command.argument(at: 0) as? [String: Any] ?? [:]
    }

    private static func syncOptions(from options: [String: Any]) throws -> SyncOptions {
        return SyncOptions(
            applyStrategy: try option("applyStrategy", options, ApplyStrategy.init(rawValue:)),
            downloadStrategy: try option("downloadStrategy", options, DownloadStrategy.init(rawValue:)),
            mandatoryApplyStrategy: try option("mandatoryApplyStrategy", options, MandatoryApplyStrategy.init(rawValue:)))
    }

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

    // A rollback belongs to the start that follows it, so it waits until the reloaded page listens.
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
