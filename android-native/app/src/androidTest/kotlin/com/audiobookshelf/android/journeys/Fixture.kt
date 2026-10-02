package com.audiobookshelf.android.journeys

import android.content.Context
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsNodeInteractionsProvider
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
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

    /** Makes the server refuse listening sync, whatever the configured mode, until reconfigured. */
    fun refuseListening(refuse: Boolean, base: String = server) {
        post("$base/__android__/refuse-listening", JSONObject().put("refuse", refuse).toString())
    }

    /** Makes the server refuse reading positions, whatever the configured mode, until reconfigured. */
    fun refuseReading(refuse: Boolean, base: String = server) {
        post("$base/__android__/refuse-reading", JSONObject().put("refuse", refuse).toString())
    }

    /** The signed-in account's server progress for one book, or null when it has none. */
    fun serverProgress(itemId: String, base: String = server): JSONObject? =
        JSONObject(get("$base/__android__/progress")).getJSONArray("progress").objects()
            .firstOrNull { it.getString("libraryItemId") == itemId && it.isNull("episodeId") }

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

fun ComposeTestRule.waitForTag(tag: String, timeoutMs: Long = 15_000) = Failures.capturing(this, "tag $tag") {
    waitUntil(timeoutMs) { onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }
}

fun ComposeTestRule.waitForText(text: String, timeoutMs: Long = 15_000, substring: Boolean = true) = Failures.capturing(this, "text $text") {
    waitUntil(timeoutMs) { onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty() }
}

fun ComposeTestRule.isShown(tag: String) = onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

fun ComposeTestRule.replaceText(tag: String, text: String) {
    onNodeWithTag(tag).performTextClearance()
    onNodeWithTag(tag).performTextInput(text)
}

fun ComposeTestRule.tap(tag: String) {
    waitForTag(tag)
    onNodeWithTag(tag).performClick()
}

fun ComposeTestRule.hideKeyboard() {
    waitForIdle()
    if (Device.device.executeShellCommand("dumpsys input_method").contains("mInputShown=true")) Device.device.pressBack()
    waitForIdle()
}

fun ComposeTestRule.pressBack() {
    waitForIdle()
    Device.device.pressBack()
    waitForIdle()
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
    if (!check()) Failures.capturing(null, "eventually") { throw ComposeTimeoutException("Condition not met within $timeoutMs ms") }
}

/**
 * Records what a failed wait was looking at, while the screen is still showing: a screenshot, every window's
 * semantics and the app's latest requests to the fixture with their answers. Nothing is recorded for passing journeys.
 * `scripts/verify-journeys.sh` pulls the screenshots; the rest goes to the test's logcat under `JourneyFailure`.
 */
object Failures {
    const val DIRECTORY = "/data/local/tmp/abs-journey-failures"
    private const val LOG = "JourneyFailure"

    fun <T> capturing(compose: ComposeTestRule?, waitingFor: String, block: () -> T): T = try {
        block()
    } catch (failure: Throwable) {
        record(compose, waitingFor)
        throw failure
    }

    private fun record(compose: ComposeTestRule?, waitingFor: String) {
        val test = Thread.currentThread().stackTrace.firstOrNull { it.className.endsWith("Journey") }
            ?.let { "${it.className.substringAfterLast('.')}-${it.methodName}-${it.lineNumber}" } ?: "journey"
        val name = "$test-${System.currentTimeMillis()}"
        android.util.Log.e(LOG, "$name waiting for $waitingFor")
        runCatching {
            Device.device.executeShellCommand("mkdir -p $DIRECTORY")
            Device.device.executeShellCommand("screencap -p $DIRECTORY/$name.png")
            android.util.Log.e(LOG, "screenshot $DIRECTORY/$name.png")
        }.onFailure { android.util.Log.e(LOG, "no screenshot: $it") }
        compose?.let { rule ->
            runCatching { rule.onAllNodes(isRoot(), useUnmergedTree = true).printToString(maxDepth = Int.MAX_VALUE) }
                .onSuccess { tree -> tree.lines().forEach { android.util.Log.e(LOG, "semantics $it") } }
                .onFailure { android.util.Log.e(LOG, "no semantics: $it") }
        }
        runCatching { Fixture.requests().filterNot { it.optString("path").startsWith("/__") }.takeLast(40) }
            .onSuccess { requests -> requests.forEach { android.util.Log.e(LOG, "request ${it.optString("method")} ${it.optString("path")} -> ${it.opt("status") ?: "no answer yet"}") } }
            .onFailure { android.util.Log.e(LOG, "no fixture requests: $it") }
    }
}

@Suppress("unused") private fun SemanticsNodeInteractionsProvider.unused() = Unit

/** Drives the system browser for the local synthetic OpenID provider, clearing Chrome's first-run screens. */
object Browser {
    private val device get() = androidx.test.uiautomator.UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val firstRun = listOf("Use without an account", "Accept & continue", "No thanks", "No, thanks", "Got it", "Continue")

    fun approve(timeoutMs: Long = 45_000) = until(timeoutMs, "Approve sign-in")

    fun waitForProvider(timeoutMs: Long = 45_000) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (device.findObject(androidx.test.uiautomator.By.text("Local OpenID")) != null) return
            dismissFirstRun()
            Thread.sleep(300)
        }
        fail("Local OpenID provider page did not appear")
    }

    fun back() { device.pressBack() }

    private fun until(timeoutMs: Long, link: String) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val target = device.findObject(androidx.test.uiautomator.By.text(link))
            if (target != null) { target.click(); return }
            dismissFirstRun()
            Thread.sleep(300)
        }
        fail("Browser never showed \"$link\"")
    }

    private fun fail(message: String): Nothing {
        val shot = File(InstrumentationRegistry.getInstrumentation().targetContext.externalCacheDir, "browser-failure.png")
        device.takeScreenshot(shot)
        throw AssertionError("$message (screenshot: ${shot.absolutePath})")
    }

    private fun dismissFirstRun() {
        for (label in firstRun) device.findObject(androidx.test.uiautomator.By.text(label))?.let { it.click(); return }
    }
}

/** Scrolls a lazy container until [tag] is composed, letting pagination load as a person would. */
fun ComposeTestRule.scrollTo(container: String, tag: String, timeoutMs: Long = 30_000) {
    val deadline = System.currentTimeMillis() + timeoutMs
    // Lazy containers can scroll to any already-loaded key directly, in either direction.
    if (runCatching { onNodeWithTag(container).performScrollToNode(hasTestTag(tag)) }.isSuccess) return
    while (!isShown(tag)) {
        if (System.currentTimeMillis() > deadline) throw ComposeTimeoutException("$tag never appeared in $container")
        onNodeWithTag(container).performTouchInput { swipeUp() }
        waitForIdle()
    }
    onNodeWithTag(container).performScrollToNode(hasTestTag(tag))
}

/** Whole-book position shown by the player, parsed from its visible clock text (m:ss or h:mm:ss). */
fun ComposeTestRule.shownSeconds(tag: String = "player-position"): Int {
    val node = onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().firstOrNull() ?: return -1
    val text = node.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.Text) { null }?.joinToString("") { it.text } ?: return -1
    return text.trim().split(':').fold(0) { total, part -> total * 60 + (part.toIntOrNull() ?: return -1) }
}

fun ComposeTestRule.waitForSeconds(atLeast: Int, timeoutMs: Long = 30_000, tag: String = "player-position") =
    waitUntil(timeoutMs) { shownSeconds(tag) >= atLeast }

object Device {
    val device get() = androidx.test.uiautomator.UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    /** Taps a media control in the system notification shade by its accessibility label. */
    fun tapNotificationControl(description: String, timeoutMs: Long = 15_000) {
        device.openNotification()
        val deadline = android.os.SystemClock.uptimeMillis() + timeoutMs
        // The media notification redraws as the position advances, which can stale a found control.
        while (true) {
            val control = device.wait(androidx.test.uiautomator.Until.findObject(androidx.test.uiautomator.By.desc(description)), 1_000)
            val clicked = control != null && runCatching { control.click() }.isSuccess
            if (clicked) break
            if (android.os.SystemClock.uptimeMillis() > deadline) {
                device.executeShellCommand("screencap -p /data/local/tmp/abs-notification.png")
                val out = java.io.ByteArrayOutputStream().also { device.dumpWindowHierarchy(it) }
                Regex("content-desc=\"[^\"]+\"").findAll(out.toString()).forEach { android.util.Log.e("AbsJourney", it.value) }
                throw AssertionError("Media notification control \"$description\" not found")
            }
        }
        device.pressBack()
    }

    fun mediaKey(code: Int) { device.pressKeyCode(code) }
}

/** Saves the screen as visual evidence in `/data/local/tmp/abs-journeys`, which outlives the app's uninstall after a run. */
fun ComposeTestRule.capture(name: String) {
    waitForIdle()
    Device.device.executeShellCommand("mkdir -p /data/local/tmp/abs-journeys")
    Device.device.executeShellCommand("screencap -p /data/local/tmp/abs-journeys/$name.png")
}
