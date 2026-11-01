package com.hotcodepush.cordova

import android.content.Context
import android.webkit.WebResourceResponse
import com.hotcodepush.core.SharedPreferencesStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

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
    fun shouldLeaveTheFrameworkFilesToCordovaWhenABundleRuns() {
        val frameworkPaths = listOf("cordova.js", "cordova_plugins.js", "plugins/cordova-plugin-device/www/device.js")
        layOutBundle("b1", *frameworkPaths.map { it to "b1" }.toTypedArray())
        loader.beginServing("b1")

        for (path in frameworkPaths) {
            assertNull(path, loader.handleRequest(path))
        }
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

    // Like Cordova's own handler, the response sets no status, and the WebView sends 200.
    private fun assertServed(content: String, response: WebResourceResponse?) {
        assertEquals(0, response?.statusCode)
        assertEquals(content, response?.data?.use { it.readBytes().decodeToString() })
    }

    private fun assertNotFound(response: WebResourceResponse?) {
        assertEquals(404, response?.statusCode)
    }
}
