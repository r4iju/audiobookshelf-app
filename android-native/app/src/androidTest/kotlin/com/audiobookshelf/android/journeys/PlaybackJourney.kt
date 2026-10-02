package com.audiobookshelf.android.journeys

import android.view.KeyEvent
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Real synthetic WAV media streamed from the fixture: an 8 s and a 12 s file, chapters at 0 and 8 s.
 * The server starts book-0 at 6 s.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PlaybackJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun reports(): List<JSONObject> = Fixture.observations().getJSONArray("reports").objects()

    @Test
    fun a_playsAcrossFilesWithMiniPlayerAndSystemControls() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.scrollTo("catalog-grid", "item-book-0")
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.waitForSeconds(9)

            compose.tap("player-collapse")
            compose.waitForTag("mini-player")
            compose.tap("back")
            compose.waitForTag("library-home")
            compose.waitForTag("mini-player")

            Device.tapNotificationControl("Pause")
            compose.waitForTag("mini-paused", 15_000)
            Device.mediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            compose.waitForTag("mini-playing", 15_000)

            compose.tap("mini-player")
            compose.tap("player-chapter-0")
            compose.waitUntil(10_000) { compose.shownSeconds() in 0..3 }
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            eventually(20_000) { reports().any { it.getString("path") == "/api/session/local-all" && it.getDouble("timeListened") > 0 } }
            compose.tap("player-close")
            compose.waitUntil(10_000) { !compose.isShown("mini-player") && !compose.isShown("player-screen") }
            eventually(10_000) { Fixture.requests().any { it.getString("path").matches(Regex("/api/session/session-\\d+/close")) } }
        }
        val sessions = reports().filter { it.getString("path") == "/api/session/local-all" }.map { it.getString("sessionId") }.toSet()
        assertEquals("One stable listening session is reported", 1, sessions.size)
    }

    @Test
    fun b_unsentListeningSurvivesProcessDeath() {
        Fixture.configure("offline-progress")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.scrollTo("catalog-grid", "item-book-1")
            compose.tap("item-book-1")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.waitForSeconds(10)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
        }
        // The orchestrator ends this process here with the report still unsent.
    }

    @Test
    fun c_relaunchPublishesRecoveredListeningAndResumesThere() {
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            eventually(30_000) {
                Fixture.observations().getJSONArray("localSessions").objects().any { it.getString("libraryItemId") == "book-1" && it.getDouble("currentTime") >= 10 }
            }
            compose.scrollTo("catalog-grid", "item-book-1")
            compose.tap("item-book-1")
            compose.waitUntil(15_000) { compose.isShown("item-progress") }
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.waitUntil(15_000) { compose.shownSeconds() >= 0 }
            assertTrue("Resumes near the recovered position, not the old server one", compose.shownSeconds() >= 7)
        }
    }

    @Test
    fun d_missingAndBrokenMediaLeaveAClearRecoverableState() {
        Fixture.configure("no-audio")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.scrollTo("catalog-grid", "item-book-2")
            compose.tap("item-book-2")
            compose.tap("play")
            compose.waitForTag("play-error", 20_000)

            Fixture.configure("broken-audio")
            compose.tap("play")
            compose.waitForTag("player-error", 30_000)
            Fixture.configure("baseline")
            compose.tap("player-retry")
            compose.waitForTag("player-playing", 30_000)
        }
    }

    @Test
    fun e_reachingTheEndMarksTheBookFinished() {
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.scrollTo("catalog-grid", "item-book-3")
            compose.tap("item-book-3")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.tap("player-chapter-1")
            repeat(2) { compose.tap("jump-forward") }
            compose.waitForTag("player-finished", 30_000)
            // Nothing plays once the book has ended, so the control offers to play rather than pause.
            compose.waitForTag("player-paused")
            eventually(20_000) {
                Fixture.observations().getJSONArray("localSessions").objects().any { it.getString("libraryItemId") == "book-3" && it.getDouble("currentTime") >= 20 }
            }
        }
    }
}
