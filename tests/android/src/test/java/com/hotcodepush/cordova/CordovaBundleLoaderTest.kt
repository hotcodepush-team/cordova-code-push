package com.hotcodepush.cordova

import android.content.Context
import android.webkit.WebResourceResponse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

/**
 * The loader's answer to Cordova's asset loader, over the plugin's own store and bundles laid out by path under the store,
 * as the core leaves them: which requests a bundle answers, with which file, and which it leaves to Cordova.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CordovaBundleLoaderTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val store = SharedPreferencesStore(context.getSharedPreferences("hotcodepush", Context.MODE_PRIVATE))
    private val loader = CordovaBundleLoader(context, store) {}

    @Test
    fun shouldLeaveTheRequestToCordovaWhenTheStartHasNotDecided() {
        layOutBundle("b1", "index.html" to "b1")
        loader.loadServedBundle("b1")

        val response = loader.handleRequest("index.html")

        assertNull(response)
    }

    @Test
    fun shouldLeaveTheRequestToCordovaWhenTheEmbeddedBundleRuns() {
        layOutBundle("b1", "index.html" to "b1")
        loader.beginServing(null)

        val response = loader.handleRequest("index.html")

        assertNull(response)
    }

    @Test
    fun shouldLeaveCordovaJsToCordovaWhenABundleRuns() {
        layOutBundle("b1", "cordova.js" to "b1")
        loader.beginServing("b1")

        val response = loader.handleRequest("cordova.js")

        assertNull(response)
    }

    @Test
    fun shouldLeaveCordovaPluginsJsToCordovaWhenABundleRuns() {
        layOutBundle("b1", "cordova_plugins.js" to "b1")
        loader.beginServing("b1")

        val response = loader.handleRequest("cordova_plugins.js")

        assertNull(response)
    }

    @Test
    fun shouldLeaveAPluginFileToCordovaWhenABundleRuns() {
        layOutBundle("b1", "plugins/cordova-plugin-device/www/device.js" to "b1")
        loader.beginServing("b1")

        val response = loader.handleRequest("plugins/cordova-plugin-device/www/device.js")

        assertNull(response)
    }

    @Test
    fun shouldServeTheStartPageWhenThePathIsEmpty() {
        layOutBundle("b1", "index.html" to "<p>b1</p>")
        loader.beginServing("b1")

        val response = loader.handleRequest("")

        assertServed("<p>b1</p>", response)
    }

    @Test
    fun shouldServeTheBundleFileWhenThePathNamesIt() {
        layOutBundle("b1", "assets/app.css" to "p {}")
        loader.beginServing("b1")

        val response = loader.handleRequest("assets/app.css")

        assertServed("p {}", response)
    }

    @Test
    fun shouldAnswerNotFoundWhenTheFileIsMissing() {
        layOutBundle("b1", "index.html" to "b1")
        loader.beginServing("b1")

        val response = loader.handleRequest("missing.html")

        assertNotFound(response)
    }

    @Test
    fun shouldAnswerNotFoundWhenThePathNamesADirectory() {
        layOutBundle("b1", "assets/app.css" to "p {}")
        loader.beginServing("b1")

        val response = loader.handleRequest("assets")

        assertNotFound(response)
    }

    @Test
    fun shouldAnswerNotFoundWhenThePathClimbsOutOfTheBundleIntoAnother() {
        layOutBundle("b1", "index.html" to "b1")
        layOutBundle("b2", "index.html" to "b2")
        loader.beginServing("b1")

        val response = loader.handleRequest("../b2/index.html")

        assertNotFound(response)
    }

    @Test
    fun shouldAnswerNotFoundWhenThePathClimbsIntoASiblingWhoseNameStartsWithTheBundleId() {
        layOutBundle("b1", "index.html" to "b1")
        layOutBundle("b10", "index.html" to "b10")
        loader.beginServing("b1")

        val response = loader.handleRequest("../b10/index.html")

        assertNotFound(response)
    }

    @Test
    fun shouldServeTheFileWhenThePathClimbsBackIntoTheBundle() {
        layOutBundle("b1", "index.html" to "<p>b1</p>", "assets/app.css" to "p {}")
        loader.beginServing("b1")

        val response = loader.handleRequest("assets/../index.html")

        assertServed("<p>b1</p>", response)
    }

    @Test
    fun shouldAnswerJavaScriptWhenTheFileIsAScript() {
        layOutBundle("b1", "main.js" to "run()")
        loader.beginServing("b1")

        val response = loader.handleRequest("main.js")

        assertEquals("application/javascript", response?.mimeType)
    }

    private fun layOutBundle(bundleId: String, vararg files: Pair<String, String>) {
        val directory = File(File(File(context.filesDir, "hotcodepush"), "www"), bundleId)
        for ((path, content) in files) {
            File(directory, path).apply { parentFile?.mkdirs() }.writeText(content)
        }
    }

    /** A file answered as Cordova's own handler answers one: its bytes, and no status of its own, which the WebView sends as 200. */
    private fun assertServed(content: String, response: WebResourceResponse?) {
        assertEquals(0, response?.statusCode)
        assertEquals(content, response?.data?.use { it.readBytes().decodeToString() })
    }

    private fun assertNotFound(response: WebResourceResponse?) {
        assertEquals(404, response?.statusCode)
    }
}
