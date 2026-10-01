package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
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
class BrowseJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun a_paginatesTheWholeLibraryAndOpensBookDetails() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.scrollTo("catalog-grid", "item-book-60")
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/libraries/books/items" && it.optString("page") == "1" })

            compose.scrollTo("catalog-grid", "item-book-0")
            compose.tap("item-book-0")
            compose.waitForTag("item-detail")
            compose.waitForText("QA Narrator")
            compose.waitForText("Synthetic two-file audio")
            compose.onNodeWithTag("item-progress").assertTextContains("30%", substring = true)
            compose.scrollTo("item-detail", "chapter-1")
            compose.onNodeWithTag("chapter-1").assertTextContains("Next chapter", substring = true)
            compose.tap("back")
            compose.waitForTag("library-home")
        }
    }

    @Test
    fun b_failedPageKeepsLoadedTitlesAndRetries() {
        Fixture.configure("page-error")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.scrollTo("catalog-grid", "page-retry")
            assertTrue(compose.isShown("item-book-59"))
            compose.tap("page-retry")
            compose.scrollTo("catalog-grid", "item-book-60")
        }
    }

    @Test
    fun c_searchFindsTitlesAndAuthorsAndFiltersSortTheCatalog() {
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.tap("tab-search")
            compose.replaceText("search-field", "Tomorrow 05")
            compose.waitForTag("search-item-book-4")
            compose.replaceText("search-field", "zzzz")
            compose.waitForTag("search-empty")
            compose.replaceText("search-field", "audiobookshelf")
            compose.tap("search-author-author")
            compose.waitForTag("filtered-items")
            compose.waitForText("Stories for Tomorrow 01")
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/libraries/books/items" })
            compose.tap("back")
            compose.tap("tab-library")

            compose.tap("open-filter")
            compose.tap("filter-group-genres")
            compose.tap("filter-genres-Mystery")
            compose.waitForText("Mystery")
            compose.waitForTag("item-book-1")
            assertFalse(compose.isShown("item-book-0"))
            compose.tap("clear-filter")
            compose.tap("open-sort")
            compose.tap("sort-direction")
            compose.waitForTag("item-book-60")
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/libraries/books/items" && it.optString("page") == "0" })
        }
    }

    @Test
    fun d_podcastSearchFindsEpisodesAndEdgeMetadataStaysReadable() {
        Fixture.configure("edge-metadata")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.waitForText("A Very Long Story Title", 20_000)
            compose.tap("library-picker")
            compose.tap("library-option-podcasts")
            compose.waitForText("Evening Stories")
            compose.tap("tab-search")
            compose.replaceText("search-field", "quiet")
            compose.waitForText("A Quiet Evening")
        }
    }
}
