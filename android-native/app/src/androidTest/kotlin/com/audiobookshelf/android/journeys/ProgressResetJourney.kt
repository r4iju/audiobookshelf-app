package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        tap("player-close")
        return start
    }

    private fun ComposeTestRule.discard() {
        tap("discard-progress")
        tap("confirm-discard-progress")
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
}
