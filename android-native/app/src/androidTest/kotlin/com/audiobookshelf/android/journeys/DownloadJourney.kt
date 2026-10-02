package com.audiobookshelf.android.journeys

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import androidx.compose.ui.test.junit4.createEmptyComposeRule

/**
 * Methods share app data in order; each runs in a fresh process, so a later method observes what
 * an earlier one left on disk after a real process restart.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class DownloadJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun downloads() = Fixture.requests().count { it.getString("path").endsWith("/download") }
    private fun streamed(itemId: String, after: Int) = Fixture.requests().drop(after).any { it.getString("path").startsWith("/api/items/$itemId/play") }

    @Test
    fun a_bookDownloadsAndPlaysAcrossItsFilesOffline() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
            val paths = Fixture.requests().map { it.getString("path") }
            assertTrue("/api/items/book-0/file/0/download" in paths && "/api/items/book-0/file/1/download" in paths)
            compose.pressBack()

            Fixture.configure("offline-library")
            val start = Fixture.requests().size
            compose.tap("tab-downloads")
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
            compose.tap("mini-player")
            compose.tap("jump-forward")
            compose.waitForSeconds(16, 10_000)
            compose.waitForText("Next chapter")
            assertFalse("Downloaded media must not stream", streamed("book-0", start))
        }
    }

    @Test
    fun b_downloadSurvivesRestartOfflineAndReportsListeningOnReconnect() {
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
            compose.tap("mini-player")
            // The previous method stopped within 5 s of the 20 s fixture's end, so playback restarts from the beginning.
            compose.waitForSeconds(3, 10_000)
            compose.tap("play-pause")
            val position = compose.shownSeconds()
            Fixture.configure("baseline")
            eventually(60_000) {
                Fixture.observations().getJSONArray("localSessions").objects().any {
                    it.getString("libraryItemId") == "book-0" && it.getDouble("currentTime") >= position && it.getDouble("timeListening") > 0
                }
            }
        }
    }

    @Test
    fun c_successfulHttpErrorPageIsRejectedAndRetryRecovers() {
        Fixture.resetAppData()
        Fixture.configure("download-error-page")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("download-retry", 45_000)
            assertFalse(compose.isShown("downloaded"))
            compose.pressBack()
            compose.tap("tab-downloads")
            compose.waitForTag("download-failed-book-0")
            assertFalse(compose.isShown("offline-book-0"))
            Fixture.configure("baseline")
            compose.tap("download-retry-book-0")
            compose.waitForTag("offline-book-0", 45_000)
        }
    }

    @Test
    fun d_offlineListeningMovesAheadLocally() {
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.waitForTag("offline-book-0")
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
            compose.tap("mini-player")
            compose.tap("jump-forward")
            compose.waitForSeconds(16, 10_000)
            compose.closePlayer()
        }
    }

    @Test
    fun e_newerRemoteRewindBecomesTheOfflineResumeWithoutRedownloading() {
        val before = downloads()
        Fixture.configure("remote-rewind")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.waitForTag("item-book-0", 20_000)
        }
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.tap("play-offline-book-0")
            compose.tap("mini-player")
            compose.tap("play-pause")
            assertTrue("A newer remote rewind replaces the local position", compose.shownSeconds() in 0..5)
        }
        assertEquals("Valid files are reused", before, downloads())
    }

    @Test
    fun f_episodeDownloadIsListedAndDeleted() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("library-picker")
            compose.tap("library-option-podcasts")
            compose.tap("item-podcast")
            compose.tap("episode-episode-morning")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/items/podcast/file/episode-morning/download" })
            compose.pressBack()
            compose.pressBack()
            compose.tap("tab-downloads")
            compose.tap("delete-download-podcast-episode-morning")
            compose.tap("confirm-delete-download")
            compose.waitUntil(10_000) { !compose.isShown("offline-podcast-episode-morning") }
            compose.waitForTag("downloads-empty")
        }
    }
}
