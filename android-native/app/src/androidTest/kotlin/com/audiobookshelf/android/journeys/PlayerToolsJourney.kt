package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PlayerToolsJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun bookmarkRequests(method: String) = Fixture.requests().filter { it.getString("method") == method && it.getString("path").startsWith("/api/me/item/book-0/bookmark") }

    @Test
    fun a_bookmarksAreAddedRenamedUsedAndDeletedOnTheServer() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.scrollTo("catalog-grid", "item-book-0")
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            val marked = compose.shownSeconds()

            compose.tap("player-bookmarks")
            compose.waitForTag("bookmarks-empty")
            compose.tap("add-bookmark")
            compose.replaceText("bookmark-title", "Kitchen")
            compose.tap("save-bookmark")
            compose.waitForText("Kitchen")
            eventually { bookmarkRequests("POST").size == 1 }

            compose.tap("edit-bookmark-0")
            compose.replaceText("bookmark-title", "Garden")
            compose.tap("save-bookmark")
            compose.waitForText("Garden")
            eventually { bookmarkRequests("PATCH").size == 1 }

            compose.tap("player-chapter-1")
            compose.waitUntil(10_000) { compose.shownSeconds() >= 8 }
            compose.tap("player-bookmarks")
            compose.tap("bookmark-0")
            compose.waitUntil(10_000) { compose.shownSeconds() == marked }

            compose.tap("player-bookmarks")
            compose.tap("delete-bookmark-0")
            compose.waitForTag("bookmarks-empty")
            eventually { bookmarkRequests("DELETE").size == 1 }
        }
    }

    @Test
    fun b_sleepTimerCountsDownCanBeExtendedAndCanceled() {
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.scrollTo("catalog-grid", "item-book-0")
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.tap("player-sleep")
            compose.tap("sleep-5")
            compose.waitUntil(10_000) { compose.shownSeconds("sleep-remaining") in 280..300 }
            val before = compose.shownSeconds("sleep-remaining")
            compose.waitUntil(10_000) { compose.shownSeconds("sleep-remaining") in 1 until before }
            compose.tap("player-sleep")
            compose.tap("sleep-add")
            compose.waitUntil(10_000) { compose.shownSeconds("sleep-remaining") >= 570 }
            compose.tap("player-sleep")
            compose.tap("sleep-cancel")
            compose.waitUntil(10_000) { !compose.isShown("sleep-remaining") }
        }
    }
}
