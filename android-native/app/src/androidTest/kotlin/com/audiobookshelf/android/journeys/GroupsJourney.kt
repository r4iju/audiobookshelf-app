package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class GroupsJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun ComposeTestRule.openGroups(kind: String) {
        tap("library-menu")
        tap("menu-$kind")
        waitForTag("groups-$kind")
    }

    private fun played(after: Int) = Fixture.requests().drop(after).filter { it.getString("method") == "POST" && it.getString("path").matches(Regex("/api/items/[^/]+/play(/.*)?")) }
        .map { it.getString("path") }

    private fun playlists(): List<JSONObject> = Fixture.observations().getJSONArray("playlists").objects()
    private fun members(playlist: JSONObject) = playlist.getJSONArray("items").objects().map { it.getString("libraryItemId") }

    /** Runs after [a_playlistEpisodeOpensItsEpisodeAndAMemberFinishedElsewhereIsSkipped]: its queue finishes book-1 on the shared fixture. */
    @Test
    fun b_establishedGroupsPlayInTheirOwnOrderAndThePlaylistContinues() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openGroups("collections")
            compose.tap("group-collection-evening")
            compose.waitForText("Stories for Tomorrow 03")
            var start = Fixture.requests().size
            compose.tap("group-play")
            compose.waitForTag("mini-playing", 15_000)
            assertEquals(listOf("/api/items/book-2/play"), played(start))
            compose.tap("group-play")
            compose.waitForTag("mini-paused", 5_000)
            assertEquals("Pausing the group must not restart a member", listOf("/api/items/book-2/play"), played(start))

            compose.pressBack()
            compose.pressBack()
            compose.openGroups("playlists")
            compose.tap("group-playlist-evening")
            start = Fixture.requests().size
            compose.tap("group-play")
            compose.waitForTag("mini-playing", 15_000)
            assertEquals(listOf("/api/items/book-1/play"), played(start))
            eventually(45_000) { played(start).contains("/api/items/book-2/play") }
        }
    }

    @Test
    fun a_playlistEpisodeOpensItsEpisodeAndAMemberFinishedElsewhereIsSkipped() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("library-picker")
            compose.tap("library-option-podcasts")
            compose.openGroups("playlists")
            compose.tap("group-playlist-podcasts")
            compose.tap("group-member-podcast:episode-morning")
            compose.waitForTag("episode-detail")
            compose.waitForText("The Morning After")
            compose.pressBack()
            compose.pressBack()
            compose.pressBack()

            compose.tap("library-picker")
            compose.tap("library-option-books")
            compose.openGroups("collections")
            compose.tap("group-collection-evening")
            compose.waitForTag("group-play")
            val start = Fixture.requests().size
            Fixture.configure("group-remote-finish")
            compose.tap("group-play")
            compose.waitForTag("mini-playing", 15_000)
            val requests = Fixture.requests().drop(start).map { it.getString("path") }
            assertTrue("Fresh progress is read before choosing a member", "/api/me" in requests)
            assertEquals(listOf("/api/items/book-1/play"), played(start))
        }
    }

    @Test
    fun c_playlistIsCreatedReorderedTrimmedAndDeleted() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openGroups("playlists")
            compose.tap("new-group")
            compose.replaceText("group-name", "Night drive")
            compose.tap("choose-book-1")
            compose.tap("choose-book-2")
            compose.tap("save-group")
            eventually { playlists().any { it.getString("name") == "Night drive" } }
            val created = playlists().first { it.getString("name") == "Night drive" }
            val id = created.getString("id")
            assertEquals(listOf("book-1", "book-2"), members(created))

            compose.waitForTag("group-detail-$id")
            compose.tap("edit-group")
            compose.tap("move-up-book-2")
            compose.tap("save-group")
            eventually { playlists().firstOrNull { it.getString("id") == id }?.let(::members) == listOf("book-2", "book-1") }
            compose.waitForTag("group-detail-$id")

            compose.tap("edit-group")
            compose.tap("remove-book-1")
            compose.tap("save-group")
            eventually { playlists().firstOrNull { it.getString("id") == id }?.let(::members) == listOf("book-2") }

            compose.waitForTag("group-detail-$id")
            compose.tap("delete-group")
            compose.tap("confirm-delete-group")
            eventually { playlists().none { it.getString("id") == id } }
            compose.waitForTag("groups-playlists")
            assertFalse(compose.isShown("group-$id"))
        }
    }

    @Test
    fun d_deniedAndFailedChangesAreNotShownAsSaved() {
        Fixture.resetAppData()
        Fixture.configure("group-forbidden")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openGroups("collections")
            assertFalse("Deleting collections needs a permission this account lacks", compose.isShown("delete-group"))
            compose.tap("new-group")
            compose.replaceText("group-name", "Not allowed")
            compose.tap("choose-book-1")
            compose.tap("save-group")
            compose.waitForTag("group-error")
            compose.hideKeyboard()
            compose.pressBack()
            compose.waitForTag("groups-collections")
            assertFalse(compose.isShown("group-collection-created-1"))
            assertTrue(Fixture.observations().getJSONArray("collections").objects().none { it.getString("name") == "Not allowed" })

            Fixture.configure("group-partial-failure")
            compose.tap("group-collection-evening")
            compose.tap("edit-group")
            compose.replaceText("group-name", "Late shelf")
            compose.tap("save-group")
            compose.waitForTag("group-error")
            assertEquals("Evening shelf", Fixture.observations().getJSONArray("collections").objects().first().getString("name"))
            compose.tap("save-group")
            eventually { Fixture.observations().getJSONArray("collections").objects().first().getString("name") == "Late shelf" }
            compose.waitForText("Late shelf")
        }
    }
}
