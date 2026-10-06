package com.hotcodepush.cordova

import android.content.Context
import android.net.ConnectivityManager
import android.webkit.MimeTypeMap
import android.webkit.WebResourceResponse
import com.hotcodepush.core.BundleLoader
import com.hotcodepush.core.EmbeddedBundle
import com.hotcodepush.core.EmbeddedBundleManifest
import com.hotcodepush.core.KeyValueStore
import com.hotcodepush.core.PlainException
import com.hotcodepush.core.WebViewGate
import java.io.File

/**
 * Cordova serves the app from `assets/www` through its asset loader, which asks the plugins first; the plugin answers
 * with the files of a bundle laid out by path under the store, so the bundle is served in the binary's place, on the same origin.
 * A switch waits for the first page, so the start is never interrupted halfway.
 */
class CordovaBundleLoader(
    private val context: Context,
    /** The core's own store, so the bundle to serve at the next start lies beside the state it belongs to. */
    private val store: KeyValueStore,
    private val reloadStartPage: () -> Unit,
) : BundleLoader {
    private val gate = WebViewGate()
    private val projectionsDirectory = File(File(context.filesDir, "hotcodepush"), "www")

    @Volatile
    private var runningBundleId: String? = persistedBundleId()

    override fun projectionDirectory(bundleId: String): File = File(projectionsDirectory, bundleId)

    override fun deleteProjection(bundleId: String) {
        projectionDirectory(bundleId).deleteRecursively()
    }

    override fun persistServedBundle(bundleId: String?) {
        store.putString(SERVED_BUNDLE_KEY, bundleId)
    }

    override fun loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId)
        gate.runWhenLoaded {
            runningBundleId = bundleId
            reloadStartPage()
        }
    }

    override fun servedBundleId(): String? = runningBundleId

    override fun isConnectionMetered(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)?.isActiveNetworkMetered ?: false

    /**
     * The answer to a request for the app's own path while a bundle runs; `null` leaves the request to Cordova,
     * which is every request under the embedded bundle and the framework's own files under any.
     */
    fun handleRequest(path: String): WebResourceResponse? {
        val bundleId = runningBundleId ?: return null
        if (isFrameworkPath(path)) return null
        val directory = projectionDirectory(bundleId).canonicalFile
        val file = File(directory, path.ifEmpty { START_PAGE }).canonicalFile
        // A path that climbs out of the bundle's directory names nothing the bundle serves.
        if (!file.path.startsWith(directory.path + File.separator) || !file.isFile) {
            return WebResourceResponse(null, null, 404, "Not Found", emptyMap(), null)
        }
        return WebResourceResponse(mimeType(file), null, file.inputStream())
    }

    fun handleWebViewLoaded() = gate.markLoaded()

    /** The activity is gone: a switch still waiting for its WebView has nowhere to go. */
    fun close() = gate.close()

    /** What `cordova prepare` adds to the app's own files: the bridge of the binary's plugins, never a bundle's. */
    private fun isFrameworkPath(path: String) = path in FRAMEWORK_FILE_PATHS || path.startsWith(FRAMEWORK_PLUGINS_PREFIX)

    /** The types the web layer loads strictly by come first; the rest is the system's table, as Cordova's own handler reads it. */
    private fun mimeType(file: File): String = when (val extension = file.extension.lowercase()) {
        "js", "mjs" -> "application/javascript"
        "wasm" -> "application/wasm"
        "" -> "text/html"
        else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
    }

    /** The bundle the last run left to serve, as long as its directory is still there. */
    private fun persistedBundleId(): String? = store.getString(SERVED_BUNDLE_KEY)?.takeIf { projectionDirectory(it).isDirectory }

    companion object {
        const val EMBEDDED_ASSET_PATH = "www"
        private val FRAMEWORK_FILE_PATHS = setOf("cordova.js", "cordova_plugins.js")
        private const val FRAMEWORK_PLUGINS_PREFIX = "plugins/"
        private const val SERVED_BUNDLE_KEY = "hotcodepush.cordova.servedBundleId"
        private const val START_PAGE = "index.html"
    }
}

/** The files compiled into the binary, `assets/www/` in the APK, addressed by the embedded manifest's hashes. */
class AssetsEmbeddedBundle(private val context: Context, manifest: EmbeddedBundleManifest?) : EmbeddedBundle {
    private val pathsBySha256 = manifest?.files.orEmpty().associate { it.sha256 to it.path }

    override fun has(sha256: String): Boolean {
        val path = pathsBySha256[sha256] ?: return false
        return runCatching { context.assets.open("${CordovaBundleLoader.EMBEDDED_ASSET_PATH}/$path").close(); true }.getOrDefault(false)
    }

    override fun copyFile(sha256: String, destination: File) {
        val path = pathsBySha256[sha256] ?: throw PlainException("No embedded file with hash $sha256")
        context.assets.open("${CordovaBundleLoader.EMBEDDED_ASSET_PATH}/$path").use { input -> destination.outputStream().use { input.copyTo(it) } }
    }
}
