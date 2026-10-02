package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PodcastJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun ComposeTestRule.top(tag: String) = onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top

    private fun ComposeTestRule.openPodcasts() {
        tap("library-picker")
        tap("library-option-podcasts")
        waitForTag("item-podcast", 20_000)
    }

    @Test
    fun a_episodesSortPlayWithEpisodeProgressAndCompletionPersists() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPodcasts()
            assertFalse("Only admins may add podcasts", compose.isShown("add-podcast"))
            compose.tap("item-podcast")
            compose.waitForTag("episode-episode-morning")
            compose.waitForTag("episode-episode")
            assertFalse(compose.isShown("feed-episodes"))
            assertTrue("Newest first", compose.top("episode-episode-morning") < compose.top("episode-episode"))
            compose.tap("episode-sort")
            compose.waitUntil(5_000) { compose.top("episode-episode") < compose.top("episode-episode-morning") }

            compose.tap("episode-play-episode")
            compose.waitForTag("player-screen", 20_000)
            compose.waitForText("A Quiet Evening")
            compose.waitForSeconds(8)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            eventually(20_000) {
                Fixture.observations().getJSONArray("localSessions").objects().any { it.getString("libraryItemId") == "podcast" && it.optString("episodeId") == "episode" && it.getDouble("currentTime") >= 8 }
            }
            compose.tap("player-collapse")

            compose.tap("episode-episode-morning")
            compose.waitForTag("episode-detail")
            compose.tap("episode-finish")
            compose.waitForTag("episode-unfinish")
            eventually { Fixture.requests().any { it.getString("method") == "PATCH" && it.getString("path") == "/api/me/progress/podcast/episode-morning" } }
            compose.tap("back")
            compose.waitForTag("episode-done-episode-morning")
        }
    }

    @Test
    fun b_adminDiscoversAndCreatesAPodcast() {
        Fixture.resetAppData()
        Fixture.configure("podcast-admin")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPodcasts()
            compose.tap("add-podcast")
            compose.replaceText("podcast-query", "New Voices")
            compose.tap("podcast-search")
            compose.tap("podcast-discovery-42")
            compose.waitForTag("podcast-title", 15_000)
            compose.waitForText("New Voices Discovery")
            compose.tap("create-podcast")
            compose.waitForTag("item-podcast-new", 20_000)
            assertTrue(Fixture.requests().any { it.getString("method") == "POST" && it.getString("path") == "/api/podcasts" })
        }
    }

    @Test
    fun c_adminQueuesFeedEpisodesThatArriveOnTheServer() {
        Fixture.resetAppData()
        Fixture.configure("podcast-admin")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPodcasts()
            compose.tap("item-podcast")
            compose.tap("feed-episodes")
            compose.tap("feed-episode-rss-next")
            compose.tap("queue-episodes")
            compose.waitForTag("queued-episodes")
            compose.waitForTag("episode-episode-new", 30_000)
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/podcasts/podcast/download-episodes" })
        }
    }

    @Test
    fun d_serverDownloadFailureArrivesInRealtime() {
        Fixture.resetAppData()
        Fixture.configure("podcast-download-failure")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPodcasts()
            compose.tap("item-podcast")
            compose.tap("feed-episodes")
            compose.tap("feed-episode-rss-next")
            compose.tap("queue-episodes")
            compose.waitForTag("feed-failure-0", 30_000)
            compose.waitForText("The Next Story")
            assertTrue(Fixture.observations().getJSONArray("realtimeAuthentications").length() > 0)
        }
    }
}
