package com.audiobookshelf.android.journeys

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File

/**
 * Imports the archive the legacy app's own exporter wrote (`LegacyMigrationExportTest`), opened from
 * a file manager. Methods share app data in order, each in a fresh process.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class MigrationJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun open(name: String) = ActivityScenario.launch<MainActivity>(
        Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse("content://com.audiobookshelf.journeys.archives/$name"), "application/octet-stream")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
    )

    private fun androidx.compose.ui.test.junit4.ComposeTestRule.isSelected(tag: String): Boolean {
        waitForTag(tag)
        return onAllNodes(androidx.compose.ui.test.hasTestTag(tag)).fetchSemanticsNodes().first()
            .config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.Selected) { null } == true
    }

    private fun downloaded(itemId: String, after: Int) = Fixture.requests().drop(after).map { it.getString("path") }.filter { it.startsWith("/api/items/$itemId/") && it.endsWith("/download") }

    @Test
    fun a_aFileThatIsNotAnExportIsRefusedAndNothingIsWritten() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        open("not-an-export.absmigration").use {
            compose.waitForTag("migration-refused")
            assertFalse(compose.isShown("start-import"))
        }
        assertFalse("Nothing is imported from a refused file", File(context.filesDir, "migration").exists())
    }

    @Test
    fun b_aCorruptFileIsReportedWhileTheRestImports() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        open("corrupt.absmigration").use {
            compose.tap("start-import")
            compose.waitForTag("migration-done", 30_000)
            compose.waitForText("did not match the export")
            compose.capture("migration-corrupt")
        }
    }

    @Test
    fun c_legacyDownloadsListeningAndPagesArriveWhenTheAccountSignsIn() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        val start = Fixture.requests().size
        open("legacy-export.absmigration").use {
            compose.waitForTag("migration-preflight")
            compose.waitForText("Stories for Tomorrow 01")
            compose.scrollTo("migration", "migration-issue")
            compose.waitForText("different account")
            compose.capture("migration-preflight")
            compose.tap("start-import")
            compose.waitForTag("migration-done", 30_000)
            compose.waitForText("Sign in to http://127.0.0.1:28765/abs as qa")
            compose.tap("migration-close")
            compose.signIn()
            eventually(30_000) {
                Fixture.observations().getJSONArray("localSessions").objects().any { it.getString("id") == "legacy-session-1" && it.getDouble("timeListening") == 7.0 }
            }
            compose.tap("open-settings")
            for (tag in listOf("jump-forward-30", "jump-back-5", "theme-dark")) assertTrue("$tag comes from the legacy settings", compose.isSelected(tag))
            compose.pressBack()
            compose.tap("tab-downloads")
            compose.waitForTag("offline-book-0")
            eventually(45_000) { downloaded("book-4", start) == listOf("/api/items/book-4/file/1/download") }
            compose.waitForTag("offline-book-4", 45_000)
            compose.capture("migration-downloads")
        }
        assertEquals("Imported files are not downloaded again", emptyList<String>(), downloaded("book-0", start))
    }

    @Test
    fun d_importedTitlesResumeOfflineWhereTheLegacyAppLeftThem() {
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.tap("read-offline-book-0")
            compose.waitForText("Page 2 of 4")
            compose.tap("reader-close")
            compose.tap("play-offline-book-0")
            compose.tap("mini-player")
            compose.tap("play-pause")
            assertTrue("Playback resumes at the legacy position", compose.shownSeconds() in 9..10)
        }
    }

    @Test
    fun e_theSameExportIsNotImportedAgain() {
        Fixture.configure("pdf-reader")
        open("legacy-export.absmigration").use {
            compose.waitForTag("migration-already")
            assertFalse(compose.isShown("start-import"))
        }
    }
}
