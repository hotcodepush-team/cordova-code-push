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
import java.io.File

/**
 * Cordova serves the app from `assets/www` through its asset loader, which asks the plugins first; the plugin answers
 * with the files of a bundle laid out by path under the store, so the bundle is served in the binary's place, on the same origin.
 * Until the start has decided, nothing is served and nothing reloads: the bundle the core loads is only recorded.
 */
class CordovaBundleLoader(
    private val context: Context,
    /** The core's own store, so the bundle to serve at the next start lies beside the state it belongs to. */
    private val store: KeyValueStore,
    private val reloadStartPage: () -> Unit,
) : BundleLoader {
    private val projectionsDirectory = File(File(context.filesDir, "hotcodepush"), "www")

    @Volatile
    private var runningBundleId: String? = null

    private var isServing = false

    /**
     * The start has decided: the page Cordova loads next is served from this bundle, `null` for the embedded one,
     * and every bundle the core loads from now on reloads the page.
     */
    @Synchronized
    fun beginServing(bundleId: String?) {
        runningBundleId = bundleId
        isServing = true
    }

    override fun projectionDirectory(bundleId: String): File = File(projectionsDirectory, bundleId)

    override fun deleteProjection(bundleId: String) {
        projectionDirectory(bundleId).deleteRecursively()
    }

    override fun persistServedBundle(bundleId: String?) {
        store.putString(SERVED_BUNDLE_KEY, bundleId)
    }

    /** Before the start has decided, the bundle is persisted for the page about to load; once a page is served, it reloads. */
    override fun loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId)
        synchronized(this) {
            if (!isServing) return
            runningBundleId = bundleId
        }
        reloadStartPage()
    }

    /** Before the start has decided, the bundle persisted to serve, which the start adopts when it is the one waiting. */
    @Synchronized
    override fun servedBundleId(): String? = if (isServing) runningBundleId else persistedBundleId()

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
