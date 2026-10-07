package com.hotcodepush.cordova

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hotcodepush.core.ChannelChoice
import com.hotcodepush.core.Clock
import com.hotcodepush.core.Configuration
import com.hotcodepush.core.Core
import com.hotcodepush.core.CoreListener
import com.hotcodepush.core.DebugScreen
import com.hotcodepush.core.DeviceFacts
import com.hotcodepush.core.DownloadStrategy
import com.hotcodepush.core.FileStore
import com.hotcodepush.core.InstallStrategy
import com.hotcodepush.core.KeyValueStore
import com.hotcodepush.core.MandatoryInstallStrategy
import com.hotcodepush.core.OkHttpClientAdapter
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.RolledBackEvent
import com.hotcodepush.core.ScheduledTask
import com.hotcodepush.core.Scheduler
import com.hotcodepush.core.SyncOptions
import com.hotcodepush.core.SyncTrigger
import com.hotcodepush.core.UpdateAvailableEvent
import com.hotcodepush.core.UpdateDownloadedEvent
import com.hotcodepush.core.UpdateFailedEvent
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
import java.io.File

/** The Cordova bridge over the shared core: every action is one call into the core, every answer one JSON object. */
class HotCodePushPlugin : CordovaPlugin(), CoreListener {
    private var core: Core? = null
    private var eventCallback: CallbackContext? = null
    private var loader: CordovaBundleLoader? = null
    private var retainedEvent: JSONObject? = null
    private val pathHandler = CordovaPluginPathHandler { path -> loader?.handleRequest(path) }
    private val scheduler = HandlerScheduler()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Cordova loads the start page right after the plugins initialize, so the start decides first which bundle that page comes from. */
    override fun pluginInitialize() {
        val context = cordova.context
        val configuration = readConfiguration(context)
        if (configuration == null) {
            LOG.e(TAG, NOT_CONFIGURED_MESSAGE)
            return
        }
        val store = SharedPreferencesStore(context.getSharedPreferences(defaultPreferencesName(context), Context.MODE_PRIVATE))
        val loader = CordovaBundleLoader(context, store, ::reloadStartPage)
        val core = Core(
            configuration = configuration,
            device = deviceFacts(context),
            store = store,
            files = FileStore(File(context.filesDir, "hotcodepush")),
            embedded = AssetsEmbeddedBundle(context, configuration.embeddedBundleManifest),
            http = OkHttpClientAdapter(),
            loader = loader,
            listener = this,
            scheduler = scheduler,
            clock = Clock { System.currentTimeMillis() },
            scope = scope,
            temporaryDirectory = File(context.cacheDir, "hotcodepush"),
        )
        this.core = core
        this.loader = loader
        loader.beginServing(core.handleAppStartBlocking())
    }

    /** A request for the running bundle's own files is answered from its directory; Cordova answers the rest from the binary. */
    override fun getPathHandler(): CordovaPluginPathHandler = pathHandler

    override fun onPause(multitasking: Boolean) {
        val core = core ?: return
        scope.launch { core.handleAppPause() }
    }

    override fun onResume(multitasking: Boolean) {
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

    /** The page left: the callback the events went to belongs to the page that is gone. */
    override fun onReset() {
        synchronized(this) { eventCallback = null }
    }

    override fun execute(action: String, args: JSONArray, callbackContext: CallbackContext): Boolean {
        val options = args.optJSONObject(0) ?: JSONObject()
        when (action) {
            "applyUpdate" -> run(callbackContext) { it.applyUpdate().toJson() }
            "checkForUpdate" -> run(callbackContext) { it.checkForUpdate().toJson() }
            "clearUpdates" -> runVoid(callbackContext) { it.clearUpdates() }
            "downloadUpdate" -> run(callbackContext) { it.downloadUpdate().toJson() }
            "getChannel" -> run(callbackContext) { it.channel().toJson() }
            "getDevice" -> run(callbackContext) { it.deviceResult().toJson() }
            "getState" -> run(callbackContext) { it.getState().toJson() }
            "listen" -> listen(callbackContext)
            "notifyReady" -> run(callbackContext) { it.notifyReady().toJson() }
            "notifyRendered" -> runVoid(callbackContext) { it.handleRendered() }
            "rollbackUpdate" -> runVoid(callbackContext) { it.rollbackUpdate(options.optStringOrNull("reason")) }
            "setAttributes" -> setAttributes(options, callbackContext)
            "setChannel" -> runVoid(callbackContext) { it.setChannel(channelChoice(options)) }
            "setRestartAllowed" -> setRestartAllowed(options, callbackContext)
            "showDebugScreen" -> showDebugScreen(callbackContext)
            "sync" -> sync(options, callbackContext)
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
        runVoid(callbackContext) { it.setAttributes(changes) }
    }

    private fun setRestartAllowed(options: JSONObject, callbackContext: CallbackContext) {
        val allowed = options.opt("allowed") as? Boolean
        if (allowed == null) {
            callbackContext.error("allowed must be a boolean")
            return
        }
        runVoid(callbackContext) { it.setRestartAllowed(allowed) }
    }

    private fun showDebugScreen(callbackContext: CallbackContext) {
        val core = core
        if (core == null) {
            callbackContext.error(NOT_CONFIGURED_MESSAGE)
            return
        }
        DebugScreen.show(cordova.activity, core)
        callbackContext.success()
    }

    private fun sync(options: JSONObject, callbackContext: CallbackContext) {
        val syncOptions = try {
            syncOptions(options)
        } catch (exception: PlainException) {
            callbackContext.error(exception.message)
            return
        }
        run(callbackContext) { it.sync(SyncTrigger.MANUAL, syncOptions).toJson() }
    }

    private fun channelChoice(options: JSONObject): ChannelChoice? =
        options.optStringOrNull("id")?.let { ChannelChoice.Id(it) } ?: options.optStringOrNull("name")?.let { ChannelChoice.Name(it) }

    /** Each stage's strategy for this call; a value outside its choices is a programming mistake and rejects the call. */
    private fun syncOptions(options: JSONObject) = SyncOptions(
        downloadStrategy = option("downloadStrategy", options, DownloadStrategy::fromWire),
        installStrategy = option("installStrategy", options, InstallStrategy::fromWire),
        mandatoryInstallStrategy = option("mandatoryInstallStrategy", options, MandatoryInstallStrategy::fromWire),
    )

    private fun <T> option(name: String, options: JSONObject, parse: (String?) -> T?): T? {
        val raw = options.optStringOrNull(name) ?: return null
        return parse(raw) ?: throw PlainException("$name is not one of its choices: $raw")
    }

    private fun run(callbackContext: CallbackContext, body: suspend (Core) -> JSONObject) {
        val core = core
        if (core == null) {
            callbackContext.error(NOT_CONFIGURED_MESSAGE)
            return
        }
        scope.launch {
            try {
                callbackContext.success(body(core))
            } catch (exception: Exception) {
                callbackContext.error(exception.message)
            }
        }
    }

    private fun runVoid(callbackContext: CallbackContext, body: suspend (Core) -> Unit) {
        val core = core
        if (core == null) {
            callbackContext.error(NOT_CONFIGURED_MESSAGE)
            return
        }
        scope.launch {
            try {
                body(core)
                callbackContext.success()
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

    /** The page Cordova starts the app on, from `config.xml`'s content source under the app's scheme and hostname. */
    private fun launchUrl(): String = ConfigXmlParser().apply { parse(cordova.context) }.launchUrl

    // The listener

    override fun updateAvailable(event: UpdateAvailableEvent) = notify("updateAvailable", event.toJson())

    override fun updateDownloaded(event: UpdateDownloadedEvent) = notify("updateDownloaded", event.toJson())

    override fun updateFailed(event: UpdateFailedEvent) = notify("updateFailed", event.toJson())

    override fun downloadProgress(releaseId: String, downloadedBytes: Long, totalBytes: Long) {
        val progress = if (totalBytes > 0) downloadedBytes.toDouble() / totalBytes else 0.0
        notify("downloadProgress", JSONObject().put("releaseId", releaseId).put("downloadedBytes", downloadedBytes).put("totalBytes", totalBytes).put("progress", progress))
    }

    override fun rolledBack(event: RolledBackEvent) = notify(RETAINED_EVENT_NAME, event.toJson())

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
        const val SDK_VERSION = "0.0.0"
        private const val NOT_CONFIGURED_MESSAGE = "HotCodePush is not configured: hotcodepush.json is missing from the app's assets. Run `npx hotcodepush init` and build the app once."
        private const val RETAINED_EVENT_NAME = "rolledBack"
        private const val TAG = "HotCodePush"

        /** The default `SharedPreferences`, the file `PreferenceManager.getDefaultSharedPreferences` names, without the dependency. */
        private fun defaultPreferencesName(context: Context) = "${context.packageName}_preferences"

        private fun readConfiguration(context: Context): Configuration? = try {
            context.assets.open("${CordovaBundleLoader.EMBEDDED_ASSET_PATH}/hotcodepush.json").bufferedReader().use { Configuration.decode(it.readText()) }
        } catch (exception: Exception) {
            null
        }

        private fun deviceFacts(context: Context): DeviceFacts {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
            return DeviceFacts(
                platform = "android",
                binaryVersion = info.versionName ?: "",
                binaryBuild = versionCode.toString(),
                osVersion = Build.VERSION.RELEASE ?: "",
                sdkVersion = SDK_VERSION,
                isDebugBuild = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0,
            )
        }

        private fun JSONObject.optStringOrNull(name: String): String? = if (isNull(name)) null else opt(name) as? String
    }
}

class SharedPreferencesStore(private val preferences: SharedPreferences) : KeyValueStore {
    override fun getString(key: String): String? = preferences.getString(key, null)

    override fun putString(key: String, value: String?) {
        preferences.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    override fun getInt(key: String): Int? = if (preferences.contains(key)) runCatching { preferences.getInt(key, 0) }.getOrNull() else null

    override fun putInt(key: String, value: Int?) {
        preferences.edit().apply { if (value == null) remove(key) else putInt(key, value) }.apply()
    }
}

class HandlerScheduler : Scheduler {
    private val handler = Handler(Looper.getMainLooper())

    override fun schedule(afterSeconds: Double, block: () -> Unit): ScheduledTask {
        val runnable = Runnable(block)
        handler.postDelayed(runnable, (afterSeconds * 1000).toLong())
        return ScheduledTask { handler.removeCallbacks(runnable) }
    }

    fun cancelAll() = handler.removeCallbacksAndMessages(null)
}
