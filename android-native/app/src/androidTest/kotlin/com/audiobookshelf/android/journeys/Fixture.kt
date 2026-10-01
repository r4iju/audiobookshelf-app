package com.audiobookshelf.android.journeys

import android.content.Context
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsNodeInteractionsProvider
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Synthetic loopback server reached through `adb reverse`; never a live server. */
object Fixture {
    private val arguments get() = InstrumentationRegistry.getArguments()
    val server: String get() = arguments.getString("absServer") ?: "http://127.0.0.1:28765/abs"
    val secondServer: String get() = arguments.getString("absSecondServer") ?: "http://127.0.0.1:28766/abs"
    val untrustedServer: String get() = arguments.getString("absUntrustedServer") ?: "https://127.0.0.1:28767/abs"

    fun configure(mode: String, base: String = server) {
        post("$base/__fixture__/configure", JSONObject().put("mode", mode).toString())
    }

    fun observations(base: String = server): JSONObject = JSONObject(get("$base/__fixture__/observations"))

    fun requests(base: String = server): List<JSONObject> = observations(base).getJSONArray("requests").objects()

    fun post(url: String, body: String): String = call(url, "POST", body)
    fun get(url: String): String = call(url, "GET", null)

    private fun call(url: String, method: String, body: String?): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 5000
        connection.readTimeout = 20000
        if (body != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray()) }
        }
        val code = connection.responseCode
        val text = (if (code < 400) connection.inputStream else connection.errorStream)?.bufferedReader()?.readText().orEmpty()
        check(code in 200..299) { "Fixture $method $url returned $code" }
        return text
    }

    /** Removes the preview app's own data before its graph is first used in this process. */
    fun resetAppData() {
        val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
        listOf(context.filesDir, context.noBackupFilesDir, File(context.applicationInfo.dataDir, "shared_prefs"), context.cacheDir, context.getExternalFilesDir(null))
            .filterNotNull().forEach { directory -> directory.listFiles()?.forEach { it.deleteRecursively() } }
    }
}

fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

fun ComposeTestRule.waitForTag(tag: String, timeoutMs: Long = 15_000) =
    waitUntil(timeoutMs) { onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

fun ComposeTestRule.waitForText(text: String, timeoutMs: Long = 15_000, substring: Boolean = true) =
    waitUntil(timeoutMs) { onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty() }

fun ComposeTestRule.isShown(tag: String) = onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

fun ComposeTestRule.replaceText(tag: String, text: String) {
    onNodeWithTag(tag).performTextClearance()
    onNodeWithTag(tag).performTextInput(text)
}

fun ComposeTestRule.tap(tag: String) {
    waitForTag(tag)
    onNodeWithTag(tag).performClick()
}

fun ComposeTestRule.signIn(server: String = Fixture.server, username: String = "qa", password: String = "qa") {
    waitForTag("server-address")
    replaceText("server-address", server)
    tap("connect")
    waitForTag("username")
    replaceText("username", username)
    replaceText("password", password)
    tap("sign-in")
    waitForTag("library-home", 20_000)
}

fun eventually(timeoutMs: Long = 15_000, check: () -> Boolean) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
        if (runCatching(check).getOrDefault(false)) return
        Thread.sleep(200)
    }
    if (!check()) throw ComposeTimeoutException("Condition not met within $timeoutMs ms")
}

@Suppress("unused") private fun SemanticsNodeInteractionsProvider.unused() = Unit
