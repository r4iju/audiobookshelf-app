package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProgressResetJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun ComposeTestRule.listenAndClose(): Int {
        tap("play")
        waitForTag("player-playing", 15_000)
        waitUntil(10_000) { shownSeconds() >= 0 }
        val start = shownSeconds()
        waitForSeconds(start + 4)
        closePlayer()
        return start
    }

    private fun ComposeTestRule.discard() {
        scrollTo("item-detail", "discard-progress")
        tap("discard-progress")
        tap("confirm-discard-progress")
    }

    private fun ComposeTestRule.waitForDiscard() = eventually(30_000) {
        !isShown("discard-progress") && !isShown("confirm-discard-progress") && !isShown("discard-pending")
    }

    @Test
    fun aDiscardedDownloadedTitleStartsAgainFromTheBeginning() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
            compose.listenAndClose()
            compose.discard()
            eventually { Fixture.serverProgress("book-0") == null }
            compose.waitUntil(5_000) { !compose.isShown("discard-progress") }

            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            val resumed = compose.shownSeconds()
            assertTrue("Discarded progress must not resume on this device, but resumed at $resumed s", resumed <= 2)
        }
    }

    @Test
    fun listeningUnsentWhenProgressIsDiscardedDoesNotBringItBack() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        Fixture.refuseListening(true)
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            val start = compose.listenAndClose()
            compose.discard()
            Fixture.refuseListening(false)
            // A discard that could not be completed yet is tried again once the server accepts listening.
            eventually(30_000) {
                if (Fixture.serverProgress("book-0") == null) return@eventually true
                if (compose.isShown("discard-progress") && !compose.isShown("confirm-discard-progress")) compose.discard()
                false
            }
            // Wait until the listening from before the discard has reached the server.
            eventually(90_000) {
                Fixture.observations().getJSONArray("localSessions").objects()
                    .any { it.getString("libraryItemId") == "book-0" && it.optDouble("currentTime") >= start + 3 }
            }
            assertNull("Discarded progress must stay discarded", Fixture.serverProgress("book-0"))
        }
    }

    @Test
    fun aPageSentJustBeforeTheDiscardDoesNotBringProgressBack() {
        Fixture.resetAppData()
        Fixture.configure("pdf-delayed")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("read-ebook")
            compose.tap("pdf-next")
            // The server holds this page write for a few seconds before saving it.
            eventually { Fixture.requests().any { it.optString("ebookLocation") == "2" } }
            compose.tap("reader-close")
            compose.discard()
            compose.waitForDiscard()
            Thread.sleep(5_000)
            assertNull("A page written before the discard must not outlive it", Fixture.serverProgress("book-0"))
        }
    }

    @Test
    fun playingWhileProgressIsBeingDiscardedDoesNotResumeTheOldPosition() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        Fixture.post("${Fixture.server}/__android__/slow-discard", """{"seconds":5}""")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.discard()
            compose.tap("play")
            val played = runCatching { compose.waitForTag("player-playing", 6_000) }.isSuccess
            compose.waitForDiscard()
            if (played) {
                Thread.sleep(2_000)
                compose.closePlayer()
                eventually(60_000) {
                    Fixture.observations().getJSONArray("localSessions").objects().any { it.getString("libraryItemId") == "book-0" }
                }
            }
            val recreated = Fixture.serverProgress("book-0")?.optDouble("currentTime")
            assertTrue("Listening from before the discard came back at $recreated s", recreated == null || recreated < 5)

            // Once discarded, the title plays from the beginning.
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            assertTrue(compose.shownSeconds() <= 2)
        }
    }

    @Test
    fun aPageLeftUnsentByAFailedResetIsNeverSentForIt() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        Fixture.refuseReading(true)
        val journal = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "listening-journal.json")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("read-ebook")
            compose.tap("pdf-next")
            eventually { Fixture.requests().any { it.optString("ebookLocation") == "2" } }
            compose.tap("reader-close")
            try {
                // Only the reset's cleanup on this device fails: its listening journal cannot be replaced.
                journal.delete()
                check(journal.mkdir())
                compose.discard()
                compose.waitForTag("discard-pending")
                Fixture.refuseReading(false)
                // Reading publication retries meanwhile; a stale page would reach the server here.
                Thread.sleep(8_000)
            } finally {
                journal.delete()
            }
            compose.waitForDiscard()
            Thread.sleep(3_000)
            assertNull("A page from before the discard must not be sent for it", Fixture.serverProgress("book-0"))
        }
    }

    @Test
    fun unreadableDiscardRequestsKeepTitlesFromPlayingAfterStartUntilResolved() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "progress-resets.json").writeText("{\"version\":1,\"resets\":[{\"account\"")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("play")
            val played = runCatching { compose.waitForTag("player-playing", 8_000) }.isSuccess
            assertFalse("A discard that cannot be read may be for this title, so it must not play", played)

            // Setting them aside is an explicit choice in Diagnostics, and keeps the unreadable file.
            compose.pressBack()
            compose.tap("open-settings")
            compose.scrollTo("settings", "open-diagnostics")
            compose.tap("open-diagnostics")
            compose.tap("resolve-unreadable-resets")
            compose.tap("confirm-resolve-unreadable-resets")
            compose.waitUntil(5_000) { !compose.isShown("unreadable-resets") }
            val kept = InstrumentationRegistry.getInstrumentation().targetContext.filesDir.listFiles().orEmpty().map { it.name }
            assertTrue("The unreadable file is kept: $kept", kept.any { it.startsWith("progress-resets.json.unreadable-") })
            compose.pressBack(); compose.pressBack()
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
        }
    }
}
