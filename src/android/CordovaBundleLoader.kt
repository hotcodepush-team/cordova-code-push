package com.hotcodepush.cordova

import android.content.Context
import android.webkit.MimeTypeMap
import android.webkit.WebResourceResponse
import com.hotcodepush.core.BundleLoader
import com.hotcodepush.core.FileStore
import com.hotcodepush.core.KeyValueStore
import com.hotcodepush.core.NetworkMonitor
import java.io.File

// Cordova's asset loader asks plugins first, so a bundle is served in place of `assets/www` on the same origin.
// Until the start decides, nothing is served or reloaded.
class CordovaBundleLoader(
    context: Context,
    // The core's own store, so the served bundle is kept beside the state it belongs to.
    private val store: KeyValueStore,
    private val reloadStartPage: () -> Unit,
) : BundleLoader {
    private val networkMonitor = NetworkMonitor(context)
    private val projectionsDirectory = File(FileStore.defaultRootDirectory(context), "www")

    @Volatile
    private var runningBundleId: String? = null

    private var isServing = false

    // `null` serves the embedded bundle. From now on, every bundle the core loads reloads the page.
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

    override fun loadServedBundle(bundleId: String?) {
        persistServedBundle(bundleId)
        synchronized(this) {
            if (!isServing) return
            runningBundleId = bundleId
        }
        reloadStartPage()
    }

    @Synchronized
    override fun servedBundleId(): String? = if (isServing) runningBundleId else persistedBundleId()

    override fun isConnectionMetered(): Boolean = networkMonitor.isConnectionMetered()

    // `null` leaves the request to Cordova: under the embedded bundle, and for the framework files under any bundle.
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

    // `cordova prepare` writes these files for the binary's plugins, so a bundle never serves them.
    private fun isFrameworkPath(path: String) = path in FRAMEWORK_FILE_PATHS || path.startsWith(FRAMEWORK_PLUGINS_PREFIX)

    // The web layer checks these types strictly. The rest come from the system table, as in Cordova's own handler.
    private fun mimeType(file: File): String = when (val extension = file.extension.lowercase()) {
        "js", "mjs" -> "application/javascript"
        "wasm" -> "application/wasm"
        "" -> "text/html"
        else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
    }

    private fun persistedBundleId(): String? = store.getString(SERVED_BUNDLE_KEY)?.takeIf { projectionDirectory(it).isDirectory }

    companion object {
        const val EMBEDDED_ASSET_PATH = "www"
        private val FRAMEWORK_FILE_PATHS = setOf("cordova.js", "cordova_plugins.js")
        private const val FRAMEWORK_PLUGINS_PREFIX = "plugins/"
        private const val SERVED_BUNDLE_KEY = "hotcodepush.servedBundleId"
        private const val START_PAGE = "index.html"
    }
}
