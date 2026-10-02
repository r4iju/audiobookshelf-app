package com.audiobookshelf.android.journeys

import android.content.pm.ActivityInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
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
class SettingsJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun ComposeTestRule.isSelected(tag: String) = onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().first()
        .config.getOrElseNullable(SemanticsProperties.Selected) { null } == true

    private fun ComposeTestRule.choose(tag: String) {
        scrollTo("settings", tag)
        tap(tag)
        waitUntil(5_000) { isSelected(tag) }
    }

    /** Everything the diagnostics screen shows: the connection summary and each recorded failure. */
    private fun ComposeTestRule.diagnosticsText(): String =
        onAllNodes(SemanticsMatcher("diagnostics") { it.config.getOrElseNullable(SemanticsProperties.TestTag) { null }?.startsWith("diagnostic") == true })
            .fetchSemanticsNodes().joinToString("\n") { node -> node.config.getOrElseNullable(SemanticsProperties.Text) { null }?.joinToString(" ") { it.text }.orEmpty() }

    @Test
    fun a_preferencesPersistAndChangeWhatTheAppDoes() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.signIn()
            compose.tap("open-settings")
            compose.choose("theme-black")
            compose.choose("haptic-off")
            compose.choose("jump-forward-5")
            compose.choose("jump-back-5")
            compose.choose("orientation-landscape")
            compose.capture("settings-landscape")
            scenario.onActivity { assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, it.requestedOrientation) }
        }
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.waitForTag("open-settings")
            scenario.onActivity { assertEquals("A locked orientation applies from launch", ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, it.requestedOrientation) }
            compose.tap("open-settings")
            for (tag in listOf("theme-black", "haptic-off", "jump-forward-5", "jump-back-5", "orientation-landscape")) {
                compose.scrollTo("settings", tag)
                assertTrue("$tag is kept after relaunch", compose.isSelected(tag))
            }
            compose.choose("orientation-none")
            scenario.onActivity { assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, it.requestedOrientation) }
            compose.pressBack()

            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.tap("play-pause")
            compose.waitForTag("player-paused")
            compose.waitForIdle()
            val start = compose.shownSeconds()
            assertTrue(compose.onAllNodes(hasContentDescription("Jump forward 5 seconds")).fetchSemanticsNodes().isNotEmpty())
            compose.tap("jump-forward")
            compose.waitUntil(5_000) { compose.shownSeconds() == start + 5 }
            compose.tap("jump-back")
            compose.waitUntil(5_000) { compose.shownSeconds() == start }
        }
    }

    @Test
    fun b_statisticsShowServerListeningTotals() {
        ActivityScenario.launch(MainActivity::class.java).use {
            val before = Fixture.requests().size
            compose.tap("library-menu")
            compose.tap("menu-statistics")
            compose.waitForText("61 minutes listened")
            compose.waitForText("3 days listened")
            compose.waitForText("0 titles finished")
            compose.waitForText("Stories for Tomorrow 03")
            assertTrue(Fixture.requests().drop(before).any { it.getString("path") == "/api/me/listening-stats" })
            compose.capture("statistics")
        }
    }

    @Test
    fun c_progressCanBeFinishedReopenedAndDiscarded() {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.scrollTo("catalog-grid", "item-book-1")
            compose.tap("item-book-1")
            compose.tap("item-finish")
            compose.waitForText("Finished")
            eventually { Fixture.serverProgress("book-1")?.optBoolean("isFinished") == true }
            compose.tap("item-unfinish")
            eventually { Fixture.serverProgress("book-1")?.optBoolean("isFinished") == false }
            compose.waitForTag("item-finish")
            compose.tap("discard-progress")
            compose.tap("confirm-discard-progress")
            eventually { Fixture.serverProgress("book-1") == null }
            compose.waitUntil(5_000) { !compose.isShown("discard-progress") }
            compose.pressBack()
            compose.scrollTo("catalog-grid", "item-book-1")
            compose.tap("item-book-1")
            compose.waitForTag("item-finish")
            assertFalse("Discarded progress stays gone after reopening", compose.isShown("discard-progress"))
        }
    }

    @Test
    fun d_diagnosticsExplainFailuresWithoutCredentials() {
        Fixture.configure("pdf-invalid")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("item-book-0")
            compose.tap("read-ebook")
            compose.waitForTag("pdf-error")
            compose.tap("reader-close")
            compose.pressBack()
            compose.tap("open-settings")
            compose.scrollTo("settings", "open-diagnostics")
            compose.tap("open-diagnostics")
            compose.waitForText("127.0.0.1:28765")
            compose.waitForTag("diagnostic-0")
            val shown = compose.diagnosticsText()
            assertTrue("The reader failure is described: $shown", "PDF" in shown)
            for (secret in listOf("Bearer", "fresh", "refresh", "password")) assertFalse("Diagnostics must not expose $secret", secret in shown)
            compose.capture("diagnostics")
        }
        Fixture.configure("baseline")
    }
}
