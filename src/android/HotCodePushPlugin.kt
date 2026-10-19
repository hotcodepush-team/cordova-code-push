package com.hotcodepush.cordova

import com.hotcodepush.core.ApplyStrategy
import com.hotcodepush.core.AssetsEmbeddedBundle
import com.hotcodepush.core.ChannelChoice
import com.hotcodepush.core.Configuration
import com.hotcodepush.core.Core
import com.hotcodepush.core.CoreListener
import com.hotcodepush.core.DebugScreen
import com.hotcodepush.core.DeviceFacts
import com.hotcodepush.core.DownloadProgressEvent
import com.hotcodepush.core.DownloadStrategy
import com.hotcodepush.core.DownloadUpdateOptions
import com.hotcodepush.core.HandlerScheduler
import com.hotcodepush.core.MandatoryApplyStrategy
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.SharedPreferencesStore
import com.hotcodepush.core.SyncOptions
import com.hotcodepush.core.SyncTrigger
import com.hotcodepush.core.UpdateAvailableEvent
import com.hotcodepush.core.UpdateDownloadedEvent
import com.hotcodepush.core.UpdateFailedEvent
import com.hotcodepush.core.UpdateRolledBackEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.apache.cordova.CallbackContext
import org.apache.cordova.ConfigXmlParser
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.CordovaPluginPathHandler
import org.apache.cordova.LOG
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONObject

/** The Cordova bridge over the shared core: every action is one call into the core, every answer one JSON object. */
class HotCodePushPlugin : CordovaPlugin(), CoreListener {
    private var core: Core? = null
    private var eventCallback: CallbackContext? = null
    private var hasPaused = false
    private var loader: CordovaBundleLoader? = null

    /** What every call rejects with while there is no core: the app loads from `file://`, the resource file is missing, or the core's reader refused it. */
    private var notConfiguredMessage = Configuration.MISSING_MESSAGE
    private var retainedEvent: JSONObject? = null
    private val pathHandler = CordovaPluginPathHandler { path -> loader?.handleRequest(path) }
    private val scheduler = HandlerScheduler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Cordova loads the start page right after the plugins initialize, so the start decides first which bundle that page comes from. */
    override fun pluginInitialize() {
        if (isInsecureFileModeEnabled()) {
            notConfiguredMessage = INSECURE_FILE_MODE_MESSAGE
            LOG.e(TAG, notConfiguredMessage)
            return
        }
        val context = cordova.context
        val configuration = try {
            Configuration.read(context, "${CordovaBundleLoader.EMBEDDED_ASSET_PATH}/hotcodepush.json")
        } catch (exception: Exception) {
            notConfiguredMessage = Configuration.resolveRefusedMessage(exception)
            null
        }
        if (configuration == null) {
            LOG.e(TAG, notConfiguredMessage)
            return
        }
        val loader = CordovaBundleLoader(context, SharedPreferencesStore(context), ::reloadStartPage)
        val core = Core(
            context = context,
            configuration = configuration,
            device = DeviceFacts.current(context, SDK_VERSION),
            embedded = AssetsEmbeddedBundle(context, configuration.embeddedBundleManifest, CordovaBundleLoader.EMBEDDED_ASSET_PATH),
            loader = loader,
            listener = this,
            scope = scope,
            scheduler = scheduler,
        )
        this.core = core
        this.loader = loader
        loader.beginServing(core.handleAppStartBlocking())
    }

    /** A request for the running bundle's own files is answered from its directory; Cordova answers the rest from the binary. */
    override fun getPathHandler(): CordovaPluginPathHandler = pathHandler

    override fun onPause(multitasking: Boolean) {
        hasPaused = true
        val core = core ?: return
        scope.launch { core.handleAppPause() }
    }

    /** Cordova resumes every plugin at the activity's first resume too, which is the start, not a return from the background. */
    override fun onResume(multitasking: Boolean) {
        if (!hasPaused) return
        val core = core ?: return
        scope.launch { core.handleAppResume() }
    }

    /** The activity took its WebView with it: nothing of this instance may fire again, or two cores would race on one store. */
    override fun onDestroy() {
        scope.cancel()
        scheduler.cancelAll()
        core = null
        loader = null
    }

    /**
     * A page started: the callback the events went to belongs to the page that is gone. A page the SDK did not load,
     * `location.reload()` or a navigation, is not reported to the core: what runs and when it is gated is the process start's.
     */
    override fun onReset() {
        synchronized(this) { eventCallback = null }
    }

    override fun execute(action: String, args: JSONArray, callbackContext: CallbackContext): Boolean {
        val options = args.optJSONObject(0) ?: JSONObject()
        when (action) {
            "applyUpdate" -> run(callbackContext) { it.applyUpdate().toJson() }
            "checkForUpdate" -> run(callbackContext) { it.checkForUpdate().toJson() }
            "clearUpdates" -> run(callbackContext) {
                it.clearUpdates()
                null
            }
            "downloadUpdate" -> run(callbackContext) { it.downloadUpdate(downloadUpdateOptions(options)).toJson() }
            "getChannel" -> run(callbackContext) { it.channel().toJson() }
            "getDevice" -> run(callbackContext) { it.deviceResult().toJson() }
            "getState" -> run(callbackContext) { it.getState().toJson() }
            "listen" -> listen(callbackContext)
            "notifyReady" -> run(callbackContext) { it.notifyReady().toJson() }
            "notifyRendered" -> run(callbackContext) {
                it.handleRendered()
                null
            }
            "rollbackUpdate" -> run(callbackContext) {
                it.rollbackUpdate(options.optStringOrNull("reason"))
                null
            }
            "setAttributes" -> setAttributes(options, callbackContext)
            "setChannel" -> run(callbackContext) {
                it.setChannel(channelChoice(options))
                null
            }
            "setRestartAllowed" -> run(callbackContext) {
                it.setRestartAllowed(options.opt("isAllowed") as? Boolean ?: throw PlainException("isAllowed must be a boolean"))
                null
            }
            "showDebugScreen" -> showDebugScreen(callbackContext)
            "sync" -> run(callbackContext) { it.sync(SyncTrigger.MANUAL, syncOptions(options)).toJson() }
            else -> return false
        }
        return true
    }

    /** The one callback the web layer registers for the life of the page; every event is answered on it. */
    private fun listen(callbackContext: CallbackContext) {
        val retained = synchronized(this) {
            eventCallback = callbackContext
            retainedEvent.also { retainedEvent = null }
        }
        retained?.let { send(it) }
    }

    private fun setAttributes(options: JSONObject, callbackContext: CallbackContext) {
        val changes = mutableMapOf<String, String?>()
        for (key in options.keys()) {
            when {
                options.isNull(key) -> changes[key] = null
                options.get(key) is String -> changes[key] = options.getString(key)
                else -> {
                    callbackContext.error("An attribute value is a string or null: $key")
                    return
                }
            }
        }
        run(callbackContext) {
            it.setAttributes(changes)
            null
        }
    }

    private fun showDebugScreen(callbackContext: CallbackContext) {
        val core = core
        if (core == null) {
            callbackContext.error(notConfiguredMessage)
            return
        }
        DebugScreen.show(cordova.activity, core)
        callbackContext.success()
    }

    private fun channelChoice(options: JSONObject): ChannelChoice? =
        options.optStringOrNull("id")?.let { ChannelChoice.Id(it) } ?: options.optStringOrNull("name")?.let { ChannelChoice.Name(it) }

    /** Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call. */
    private fun syncOptions(options: JSONObject) = SyncOptions(
        applyStrategy = option("applyStrategy", options, ApplyStrategy::fromWire),
        downloadStrategy = option("downloadStrategy", options, DownloadStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", options, MandatoryApplyStrategy::fromWire),
    )

    /** The apply strategies for this call; the download strategy is pinned to `auto`. */
    private fun downloadUpdateOptions(options: JSONObject) = DownloadUpdateOptions(
        applyStrategy = option("applyStrategy", options, ApplyStrategy::fromWire),
        mandatoryApplyStrategy = option("mandatoryApplyStrategy", options, MandatoryApplyStrategy::fromWire),
    )

    private fun <T> option(name: String, options: JSONObject, parse: (String?) -> T?): T? {
        val raw = options.optStringOrNull(name) ?: return null
        return parse(raw) ?: throw PlainException("$name is not one of its choices: $raw")
    }

    /** Answers the body's result, or `success()` with no message when an action that returns nothing ends its body in `null`. */
    private fun run(callbackContext: CallbackContext, body: suspend (Core) -> JSONObject?) {
        val core = core
        if (core == null) {
            callbackContext.error(notConfiguredMessage)
            return
        }
        scope.launch {
            try {
                val result = body(core)
                if (result == null) callbackContext.success() else callbackContext.success(result)
            } catch (exception: Exception) {
                callbackContext.error(exception.message)
            }
        }
    }

    /**
     * The SDK's own reload: the departing page loses its callback first, so an event the core sends with the reload,
     * a rollback's above all, is kept for the page that follows.
     */
    private fun reloadStartPage() {
        synchronized(this) { eventCallback = null }
        cordova.activity.runOnUiThread { webView.loadUrlIntoView(launchUrl(), false) }
    }

    /** Cordova loads the app from `file://` then, where its asset loader, and with it the plugin, never answers a request. */
    private fun isInsecureFileModeEnabled(): Boolean = preferences.getBoolean(INSECURE_FILE_MODE_PREFERENCE, false)

    /** The page Cordova starts the app on, from `config.xml`'s content source under the app's scheme and hostname. */
    private fun launchUrl(): String = ConfigXmlParser().apply { parse(cordova.context) }.launchUrl

    // The listener

    override fun updateAvailable(event: UpdateAvailableEvent) = notify("updateAvailable", event.toJson())

    override fun updateDownloaded(event: UpdateDownloadedEvent) = notify("updateDownloaded", event.toJson())

    override fun updateFailed(event: UpdateFailedEvent) = notify("updateFailed", event.toJson())

    override fun downloadProgress(event: DownloadProgressEvent) = notify("downloadProgress", event.toJson())

    override fun updateRolledBack(event: UpdateRolledBackEvent) = notify(RETAINED_EVENT_NAME, event.toJson())

    private fun notify(eventName: String, data: JSONObject) = send(JSONObject().put("eventName", eventName).put("data", data))

    /** An event goes to the page's callback; a rollback is kept until the reloaded page listens, since it belongs to the start that follows it. */
    private fun send(event: JSONObject) {
        val callback = synchronized(this) {
            if (eventCallback == null && event.getString("eventName") == RETAINED_EVENT_NAME) retainedEvent = event
            eventCallback
        } ?: return
        callback.sendPluginResult(PluginResult(PluginResult.Status.OK, event).apply { keepCallback = true })
    }

    companion object {
        private const val INSECURE_FILE_MODE_PREFERENCE = "AndroidInsecureFileModeEnabled"
        private const val INSECURE_FILE_MODE_MESSAGE = "HotCodePush is off: the $INSECURE_FILE_MODE_PREFERENCE preference loads the app from file://, where no update can be served. Remove the preference from config.xml to take updates."
        private const val RETAINED_EVENT_NAME = "updateRolledBack"
        private const val TAG = "HotCodePush"

        private fun JSONObject.optStringOrNull(name: String): String? = if (isNull(name)) null else opt(name) as? String
    }
}
