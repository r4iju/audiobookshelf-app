package com.audiobookshelf.android.journeys

import android.content.Intent
import androidx.lifecycle.Lifecycle
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.regex.Pattern

@RunWith(AndroidJUnit4::class)
class LocalFilesJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private val target get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun downloadedEbook() = File(target.filesDir, "downloads").walk().first { it.isFile && it.name.endsWith(".epub") }

    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    /** What the other app could do with the opened file, as it shows it. */
    private fun otherAppReport(): String {
        val shown = Device.device.wait(Until.findObject(By.textStartsWith("read ")), 15_000)
            ?: throw AssertionError("The other app never received the file")
        return shown.text.also { Device.device.pressBack() }
    }

    private fun downloadEbook() {
        Fixture.resetAppData()
        Fixture.configure("epub-reader")
    }

    private fun androidx.compose.ui.test.junit4.ComposeTestRule.downloadAndShowDownloads() {
        signIn()
        tap("item-book-0")
        tap("download")
        waitForTag("downloaded", 45_000)
        pressBack()
        tap("tab-downloads")
    }

    @Test
    fun aDownloadedEbookOpensInAnotherAppThatCanReadOnlyThatFile() {
        downloadEbook()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.downloadAndShowDownloads()
            compose.tap("open-elsewhere-book-0")
            val report = otherAppReport()
            val ebook = downloadedEbook()
            assertTrue("The other app reads the downloaded file itself: $report", report.contains("read ${ebook.length()} sha ${sha(ebook)}"))
            assertTrue("Opening grants reading only: $report", report.contains("write refused"))
            assertTrue("Nothing else is exposed: $report", report.contains("others refused"))
        }
    }

    @Test
    fun withoutAnAppForTheFormatTheReasonIsShown() {
        downloadEbook()
        // Nothing on the emulator opens MOBI, one of the formats this app leaves to other apps.
        Fixture.post("${Fixture.server}/__android__/ebook-format", """{"format":"mobi"}""")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.downloadAndShowDownloads()
            compose.tap("open-elsewhere-book-0")
            compose.waitForText("No app on this device opens MOBI files")
        }
    }

    @Test
    fun aMissingDownloadedFileIsReportedAndDownloadsAgain() {
        downloadEbook()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.downloadAndShowDownloads()
            // Removed by another app or a file manager while this app was in the background.
            scenario.moveToState(Lifecycle.State.STARTED)
            assertTrue(downloadedEbook().delete())
            scenario.moveToState(Lifecycle.State.RESUMED)
            compose.waitForText("Some files are missing from this device")
            assertTrue("A missing file is not offered for opening", !compose.isShown("open-elsewhere-book-0"))
            compose.tap("download-retry-book-0")
            compose.waitForTag("open-elsewhere-book-0", 45_000)
            compose.tap("open-elsewhere-book-0")
            val ebook = downloadedEbook()
            assertTrue(otherAppReport().contains("read ${ebook.length()} sha ${sha(ebook)}"))
        }
    }

    /** Picks [name] under Download in the system folder picker, wherever the picker starts, and allows access. */
    private fun chooseFolder(name: String) {
        val device = Device.device
        check(device.wait(Until.hasObject(By.pkg("com.google.android.documentsui")), 15_000)) { "The folder picker did not open" }
        if (!device.wait(Until.hasObject(By.text(name)), 3_000)) device.wait(Until.findObject(By.text("Download")), 10_000).click()
        device.wait(Until.findObject(By.text(name)), 10_000).click()
        device.wait(Until.findObject(By.text(Pattern.compile("use this folder", Pattern.CASE_INSENSITIVE))), 10_000).click()
        device.wait(Until.findObject(By.text(Pattern.compile("allow", Pattern.CASE_INSENSITIVE))), 10_000).click()
    }

    @Test
    fun downloadsGoToAChosenFolderAndRecoverWhenItsAccessIsRemoved() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        val folder = "/sdcard/Download/AbsJourney"
        Device.device.executeShellCommand("rm -rf $folder")
        Device.device.executeShellCommand("mkdir -p $folder")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("open-settings")
            compose.scrollTo("settings", "choose-download-folder")
            compose.tap("choose-download-folder")
            chooseFolder("AbsJourney")
            compose.waitForText("Downloads are saved in AbsJourney")
            compose.pressBack()

            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
            val saved = Device.device.executeShellCommand("find $folder -type f").lines().filter { it.isNotBlank() }
            assertEquals("Both audio files, and nothing else, are in the chosen folder: $saved", 2, saved.count { "/Stories for Tomorrow 01/" in it })
            assertTrue("No second copy stays in app storage", File(target.filesDir, "downloads").walk().none { it.isFile && it.name.startsWith("track-") })
            compose.pressBack()

            Fixture.configure("offline-library")
            compose.tap("tab-downloads")
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
            compose.tap("mini-player")
            compose.tap("player-close")

            // The grant is gone, as after the user removes the app's access to the folder.
            target.contentResolver.persistedUriPermissions.forEach {
                target.contentResolver.releasePersistableUriPermission(it.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
        }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.waitForTag("folder-access-lost")
            compose.tap("play-offline-book-0")
            compose.waitForText("access to AbsJourney")
            assertTrue("Nothing plays without access", !compose.isShown("mini-playing"))

            compose.tap("choose-folder-again")
            chooseFolder("AbsJourney")
            compose.waitUntil(10_000) { !compose.isShown("folder-access-lost") }
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
        }
    }
}
