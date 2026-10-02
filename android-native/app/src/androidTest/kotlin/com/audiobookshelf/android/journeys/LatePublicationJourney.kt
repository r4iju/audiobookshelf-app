package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.json.JSONObject
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Writes whose answer is lost while the server is still applying them. Server 2.30 does not order
 * requests for one session or title, so the original can land after a retry, or after a discard.
 */
@RunWith(AndroidJUnit4::class)
class LatePublicationJourney {
    @get:Rule val compose = createEmptyComposeRule()

    /** The next [kind] write loses its answer and is applied by the server [seconds] later. */
    private fun holdLate(kind: String, seconds: Int) = Fixture.post("${Fixture.server}/__android__/hold-late", """{"kind":"$kind","seconds":$seconds}""")

    private fun lateApplied() = JSONObject(Fixture.post("${Fixture.server}/__android__/late-applied", "{}")).getJSONArray("applied").length()

    private fun heldLate() = Fixture.requests().any { it.optBoolean("heldLate") }

    private fun sessions(itemId: String) = Fixture.observations().getJSONArray("localSessions").objects().filter { it.getString("libraryItemId") == itemId }

    private fun ComposeTestRule.discard() {
        scrollTo("item-detail", "discard-progress")
        tap("discard-progress")
        tap("confirm-discard-progress")
    }

    /** Once the late write has landed, a discard held for it goes ahead only at the user's explicit choice. */
    private fun ComposeTestRule.discardDespiteUncertainty(): Boolean {
        val held = isShown("discard-uncertain")
        if (held) {
            tap("discard-anyway")
            tap("confirm-discard-anyway")
        }
        eventually(30_000) { !isShown("discard-pending") && !isShown("discard-uncertain") }
        return held
    }

    @Test
    fun listeningThatReachesTheServerAfterADiscardDoesNotBringProgressBack() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        holdLate("local-all", 15)
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.waitUntil(10_000) { compose.shownSeconds() >= 0 }
            val start = compose.shownSeconds()
            compose.waitForSeconds(start + 4)
            compose.tap("player-close")
            eventually(20_000) { heldLate() }
            // The lost write is sent again, and that copy is acknowledged.
            eventually(30_000) { sessions("book-0").any { it.optDouble("currentTime") >= start + 3 } }
            compose.discard()
            eventually(40_000) { lateApplied() > 0 }
            Thread.sleep(2_000)
            val held = compose.discardDespiteUncertainty()
            Thread.sleep(3_000)
            assertNull("Listening that reached the server after the discard brought its progress back", Fixture.serverProgress("book-0"))
            assertTrue("The discard waits for the user while an earlier write may still arrive", held)
        }
    }

    @Test
    fun listeningThatArrivesLateDoesNotShrinkTheListeningHistory() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.waitUntil(10_000) { compose.shownSeconds() >= 0 }
            holdLate("local-all", 12)
            compose.waitForSeconds(compose.shownSeconds() + 5)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            eventually(20_000) { heldLate() }
            compose.tap("play-pause")
            compose.waitForTag("player-playing", 15_000)
            compose.waitForSeconds(compose.shownSeconds() + 5)
            compose.tap("player-close")
            eventually(40_000) { lateApplied() > 0 }
            Thread.sleep(2_000)
            val listened = sessions("book-0").sumOf { it.optDouble("timeListening") }
            assertTrue("About 10 s were listened, but the server's sessions keep $listened s", listened >= 8)
        }
    }

    @Test
    fun aPageThatReachesTheServerAfterADiscardDoesNotBringProgressBack() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        holdLate("reading", 12)
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("read-ebook")
            compose.tap("pdf-next")
            eventually(20_000) { heldLate() }
            // The lost page is sent again, and that copy is acknowledged.
            eventually(30_000) { Fixture.serverProgress("book-0")?.optString("ebookLocation") == "2" }
            compose.tap("reader-close")
            compose.discard()
            eventually(40_000) { lateApplied() > 0 }
            Thread.sleep(2_000)
            val held = compose.discardDespiteUncertainty()
            Thread.sleep(3_000)
            assertNull("A page that reached the server after the discard brought its progress back", Fixture.serverProgress("book-0"))
            assertTrue("The discard waits for the user while an earlier page may still arrive", held)
        }
    }
}
