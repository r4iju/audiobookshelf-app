package com.audiobookshelf.android.journeys

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
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

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class PdfJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun ComposeTestRule.openPdf() {
        tap("item-book-0")
        tap("read-ebook")
    }

    private fun serverPage() = Fixture.observations().getJSONArray("readingProgress").objects()
        .firstOrNull { it.getString("libraryItemId") == "book-0" }?.optString("ebookLocation")

    private fun publications(after: Int) = Fixture.requests().drop(after).filter { it.getString("method") == "PATCH" && it.getString("path") == "/api/me/progress/book-0" && it.has("ebookLocation") }

    /** Text the renderer extracted from the shown page, exposed for accessibility. */
    private fun ComposeTestRule.pageText(): String = onAllNodes(hasTestTag("pdf-document")).fetchSemanticsNodes().firstOrNull()
        ?.config?.getOrElseNullable(SemanticsProperties.StateDescription) { null }.orEmpty()

    private fun ComposeTestRule.pageBounds() = onAllNodes(hasTestTag("pdf-page-image")).fetchSemanticsNodes().first().boundsInRoot

    private fun ComposeTestRule.isOn(tag: String) = onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().first()
        .config.getOrElseNullable(SemanticsProperties.ToggleableState) { null } == ToggleableState.On

    @Test
    fun a_pagesTurnArePublishedAndReopenWhereLeft() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPdf()
            compose.waitForText("Page 1 of 4")
            compose.waitUntil(10_000) { "Passage 1" in compose.pageText() }
            compose.tap("pdf-next")
            compose.waitForText("Page 2 of 4")
            compose.waitUntil(10_000) { "Stories for Tomorrow - Passage 2" in compose.pageText() }
            compose.capture("pdf-page-2")
            eventually { serverPage() == "2" }
            compose.tap("reader-close")
            compose.tap("read-ebook")
            compose.waitForText("Page 2 of 4")
        }
    }

    @Test
    fun b_newerServerPageIsWhereReadingResumes() {
        Fixture.configure("pdf-remote")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.openPdf()
            compose.waitForText("Page 4 of 4")
        }
    }

    private fun newerPageSurvives(mode: String) {
        Fixture.resetAppData()
        Fixture.configure(mode)
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPdf()
            compose.waitForText("Page 1 of 4")
            val start = Fixture.requests().size
            compose.tap("pdf-next")
            eventually(5_000) { publications(start).any { it.getString("ebookLocation") == "2" } }
            compose.tap("pdf-next")
            compose.waitForText("Page 3 of 4")
            if (mode == "pdf-double-failure") {
                eventually(10_000) { publications(start).any { it.getString("ebookLocation") == "3" && !it.optBoolean("applied", true) } }
            }
            eventually(20_000) { serverPage() == "3" }
            Thread.sleep(4_000)
            assertEquals("An older publication must not replace the newer page", "3", serverPage())
            compose.tap("reader-close")
            compose.tap("read-ebook")
            compose.waitForText("Page 3 of 4")
        }
    }

    @Test fun c_newerPageSurvivesAnOlderPublicationInFlight() = newerPageSurvives("pdf-delayed")

    @Test fun d_newerPageSurvivesAnAppliedPublicationWithLostResponse() = newerPageSurvives("pdf-lost-ack")

    @Test fun e_newerPageSurvivesALostAcknowledgmentThenRejectedRetry() = newerPageSurvives("pdf-double-failure")

    @Test
    fun f_invalidDocumentIsExplainedAndRetryOpensIt() {
        Fixture.resetAppData()
        Fixture.configure("pdf-invalid")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPdf()
            compose.waitForTag("pdf-error")
            Fixture.configure("pdf-reader")
            compose.tap("pdf-retry")
            compose.waitForText("Page 1 of 4")
        }
    }

    @Test
    fun g_rotatedAndLongDocumentsRenderAndNavigate() {
        Fixture.resetAppData()
        Fixture.configure("pdf-rotated")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.openPdf()
            compose.waitForText("Page 1 of 4")
            compose.waitUntil(10_000) { compose.isShown("pdf-page-image") }
            val rotated = compose.pageBounds()
            assertTrue("A page rotated by the document is shown landscape", rotated.width > rotated.height)
            compose.capture("pdf-rotated")
            compose.tap("pdf-rotate")
            compose.waitUntil(10_000) { compose.pageBounds().let { it.height > it.width } }
            compose.waitForText("Page 1 of 4")
            compose.tap("reader-close")
            compose.pressBack()

            Fixture.configure("pdf-long")
            compose.openPdf()
            compose.waitForText("Page 1 of 120")
            compose.tap("pdf-next")
            compose.tap("pdf-next")
            compose.waitForText("Page 3 of 120")
            compose.waitUntil(10_000) { "Passage 3" in compose.pageText() }
        }
    }

    @Test
    fun h_supplementaryDocumentKeepsItsOwnPageWithoutPublishing() {
        Fixture.resetAppData()
        Fixture.configure("pdf-remote")
        Fixture.configure("pdf-supplementary")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            val start = Fixture.requests().size
            compose.tap("read-file-notes")
            compose.waitForText("Page 1 of 2")
            compose.waitUntil(10_000) { "Listening notes - Passage 1" in compose.pageText() }
            compose.tap("pdf-next")
            compose.waitForText("Page 2 of 2")
            compose.tap("reader-close")
            compose.tap("read-ebook")
            compose.waitForText("Page 4 of 4")
            compose.tap("reader-close")
            compose.tap("read-file-notes")
            compose.waitForText("Page 2 of 2")
            assertTrue("Supplementary pages are not reading progress", publications(start).isEmpty())
            assertEquals("4", serverPage())
        }
    }

    @Test
    fun i_readingWhileListeningKeepsAudioAndTheDisplayPreference() {
        Fixture.resetAppData()
        Fixture.configure("pdf-audio")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.pressBack()
            compose.tap("read-ebook")
            compose.waitForText("Page 1 of 4")
            compose.waitForTag("mini-playing")
            compose.tap("pdf-next")
            compose.waitForText("Page 2 of 4")
            assertTrue("Turning pages must not stop listening", compose.isShown("mini-playing"))
            compose.tap("mini-play-pause")
            compose.waitForTag("mini-paused")
            assertFalse(compose.isOn("pdf-continuous"))
            compose.tap("pdf-continuous")
            compose.capture("pdf-continuous-listening")
            compose.tap("reader-close")
            compose.tap("read-ebook")
            compose.waitForText("Page 2 of 4")
            assertTrue("The display preference is kept", compose.isOn("pdf-continuous"))
        }
    }

    @Test
    fun j_downloadedDocumentOpensOfflineAtTheServerPage() {
        Fixture.resetAppData()
        Fixture.configure("pdf-remote")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
            assertTrue(Fixture.requests().any { it.getString("path") == "/api/items/book-0/file/pdf/download" })
        }
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.tap("read-offline-book-0")
            compose.waitForText("Page 4 of 4")
            compose.waitUntil(10_000) { "Passage 4" in compose.pageText() }
        }
    }
}
