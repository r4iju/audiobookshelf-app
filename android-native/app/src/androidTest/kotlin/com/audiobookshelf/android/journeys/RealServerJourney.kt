package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs

/**
 * Main journeys against an unmodified, throwaway Audiobookshelf 2.30.0 container with a synthetic library and
 * synthetic accounts (`scripts/verify-real-server.sh`). Skipped unless that script passes the server's address.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class RealServerJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Before fun requireServer() = assumeTrue("needs scripts/verify-real-server.sh", RealServer.address != null)

    @Test
    fun a_passwordSignInBrowsesAndStreamsAcrossFilesWithProgressOnTheServer() {
        Fixture.resetAppData()
        val book = RealServer.itemId("The Long Tide")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn(RealServer.address!!, RealServer.USER, RealServer.PASSWORD)
            // Compare the visible whole-book clock to server progress across file/chapter boundaries.
            compose.tap("open-settings")
            compose.scrollTo("settings", "chapter-track")
            compose.tap("chapter-track")
            compose.pressBack()
            compose.openItem(book)
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            // Each of the book's three files is 30 s long, so 33 s is into the second file.
            compose.waitForSeconds(33, 60_000)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            val shown = compose.shownSeconds()
            compose.tap("player-close")
            eventually(20_000) { RealServer.progress(book)?.let { abs(it.getDouble("currentTime") - shown) <= 2 } == true }
        }
    }

    @Test
    fun b_pdfPageTurnIsSavedOnTheServer() {
        val pdf = RealServer.itemId("Field Guide to Quiet")
        Fixture.resetAppData()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn(RealServer.address!!, RealServer.USER, RealServer.PASSWORD)
            compose.openItem(pdf)
            compose.tap("read-ebook")
            compose.waitForText("Page 1 of 120", 30_000)
            compose.tap("pdf-next")
            compose.waitForText("Page 2 of 120")
            eventually(20_000) { RealServer.progress(pdf)?.optString("ebookLocation") == "2" }
        }
    }

    @Test
    fun c_offlineListeningOnADownloadReachesTheServerAfterReconnect() {
        val book = RealServer.itemId("Salt and Signal")
        Fixture.resetAppData()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn(RealServer.address!!, RealServer.USER, RealServer.PASSWORD)
            compose.openItem(book)
            compose.tap("download")
            compose.waitForTag("downloaded", 60_000)
            compose.pressBack()
            compose.waitForTag("library-home")
            try {
                Network.off()
                compose.tap("tab-downloads")
                compose.tap("play-offline-$book")
                compose.waitForTag("mini-playing", 15_000)
                compose.tap("mini-player")
                compose.waitForSeconds(8, 30_000)
                compose.tap("play-pause")
                compose.waitForTag("player-paused")
                val shown = compose.shownSeconds()
                compose.tap("player-close")
                Network.on()
                eventually(60_000) { RealServer.progress(book)?.let { abs(it.getDouble("currentTime") - shown) <= 2 } == true }
            } finally {
                Network.on()
            }
        }
    }

    /**
     * Fails on 2.30.0: a local session that creates a title's first progress is stored at its end but not finished
     * (the server applies its finished rule only to existing progress). Open; see android-native/HANDOFF.md.
     */
    @Test
    fun d_finishingADownloadOfflineMarksItFinishedOnTheServerAfterReconnect() {
        val book = RealServer.itemId("A Very Long Story Title")
        Fixture.resetAppData()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn(RealServer.address!!, RealServer.USER, RealServer.PASSWORD)
            compose.openItem(book)
            compose.tap("download")
            compose.waitForTag("downloaded", 60_000)
            compose.pressBack()
            compose.waitForTag("library-home")
            try {
                Network.off()
                compose.tap("tab-downloads")
                compose.tap("play-offline-$book")
                compose.waitForTag("mini-playing", 15_000)
                compose.tap("mini-player")
                // The book is one 20 s file; it plays to its end.
                compose.waitForTag("player-finished", 40_000)
                compose.capture("real-server-offline-finished")
                Network.on()
                eventually(60_000) { RealServer.progress(book)?.optBoolean("isFinished") == true }
            } finally {
                Network.on()
            }
        }
    }
}

private fun androidx.compose.ui.test.junit4.ComposeTestRule.openItem(id: String) {
    Failures.capturing(this, "item-$id in the catalog") { scrollTo("catalog-grid", "item-$id") }
    tap("item-$id")
}

/** The throwaway 2.30.0 container's own API, read as the synthetic account the app signs in with. */
object RealServer {
    const val USER = "qa"
    const val PASSWORD = "qa-pass"
    val address: String? get() = InstrumentationRegistry.getArguments().getString("absRealServer")
    private val token by lazy {
        JSONObject(call("/login", "POST", JSONObject().put("username", USER).put("password", PASSWORD).toString()))
            .getJSONObject("user").getString("accessToken")
    }

    fun itemId(title: String): String {
        val books = JSONObject(call("/api/libraries")).getJSONArray("libraries").objects().first { it.getString("mediaType") == "book" }
        return JSONObject(call("/api/libraries/${books.getString("id")}/items?limit=200")).getJSONArray("results").objects()
            .first { it.getJSONObject("media").getJSONObject("metadata").getString("title") == title }.getString("id")
    }

    /** The account's stored progress for a book, or null when it has none. */
    fun progress(itemId: String): JSONObject? = runCatching { JSONObject(call("/api/me/progress/$itemId")) }.getOrNull()

    private fun call(path: String, method: String = "GET", body: String? = null): String {
        val connection = URL(address + path).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 5000
        connection.readTimeout = 20000
        if (path == "/login") connection.setRequestProperty("x-return-tokens", "true") else connection.setRequestProperty("Authorization", "Bearer $token")
        if (body != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray()) }
        }
        check(connection.responseCode in 200..299) { "$method $path returned ${connection.responseCode}" }
        return connection.inputStream.bufferedReader().readText()
    }
}

/** The emulator's own connectivity; the real server is only reachable through it (10.0.2.2), not through adb reverse. */
object Network {
    fun off() = listOf("svc wifi disable", "svc data disable").forEach { Device.device.executeShellCommand(it) }
    fun on() = listOf("svc wifi enable", "svc data enable").forEach { Device.device.executeShellCommand(it) }
}
