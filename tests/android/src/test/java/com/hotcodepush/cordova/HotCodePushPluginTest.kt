package com.hotcodepush.cordova

import android.content.Context
import android.content.ContextWrapper
import android.content.res.AssetManager
import com.hotcodepush.core.Core
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaInterface
import org.apache.cordova.CordovaPreferences
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.timeout
import org.mockito.Mockito.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** A call's options and its answer, over a plugin Cordova initialized on a core that records its calls. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HotCodePushPluginTest {
    private val plugin = HotCodePushPlugin()

    @Test
    fun shouldRejectTheSyncWhenItsApplyStrategyIsNotOneOfItsChoices() {
        mockConstruction(Core::class.java).use {
            initializePlugin()
            val callbackContext = mock(CallbackContext::class.java)

            plugin.execute("sync", JSONArray().put(JSONObject().put("applyStrategy", "later")), callbackContext)

            verify(callbackContext, timeout(CALL_TIMEOUT_MILLIS)).error("applyStrategy is not one of its choices: later")
        }
    }

    /** The plugin as Cordova initializes it in an app whose assets hold a valid resource file. */
    private fun initializePlugin() {
        val context = contextWithResourceFile()
        val cordova = mock(CordovaInterface::class.java)
        `when`(cordova.context).thenReturn(context)
        plugin.privateInitialize("HotCodePush", cordova, null, CordovaPreferences())
    }

    private fun contextWithResourceFile(): Context {
        val resourceAssets = mock(AssetManager::class.java)
        `when`(resourceAssets.open("www/hotcodepush.json")).thenAnswer { RESOURCE_FILE.byteInputStream() }
        return object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun getAssets(): AssetManager = resourceAssets
        }
    }

    companion object {
        /** How long a test waits for a call's coroutine, which runs on the IO dispatcher. */
        const val CALL_TIMEOUT_MILLIS = 5_000L

        const val RESOURCE_FILE =
            """{"appId":"0b6d5c1e-2f3a-4b5c-8d9e-0f1a2b3c4d5e","channelId":null,"checkIntervalSeconds":60,"builtAt":"2026-10-08T00:00:00.000Z","fingerprint":null,"embeddedBundleManifest":null}"""
    }
}
