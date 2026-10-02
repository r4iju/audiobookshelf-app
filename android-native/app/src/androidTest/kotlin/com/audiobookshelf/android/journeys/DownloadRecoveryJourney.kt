package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import com.audiobookshelf.android.download.DownloadStore
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest

@RunWith(AndroidJUnit4::class)
class DownloadRecoveryJourney {
    @get:Rule val compose = createEmptyComposeRule()
    private val files get() = InstrumentationRegistry.getInstrumentation().targetContext.filesDir
    private fun saved() = DownloadStore(File(files, "downloads.json")).records.value.singleOrNull()
    private fun control(mode: String) = Fixture.post("${Fixture.server}/__android__/download-control", JSONObject().put("mode", mode).toString())
    private var requestStart = 0
    private fun audioRequests() = Fixture.requests().drop(requestStart).count { it.getString("path").matches(Regex("/api/items/book-0/file/[01]/download")) }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toList()

    @Test
    fun failedPdfRetryThenCancelKeepsCompletedAudioAndFinishesOffline() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        requestStart = Fixture.requests().size
        control("fail")
        lateinit var retained: Map<String, List<Byte>>
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("server-address")
            compose.replaceText("server-address", Fixture.server)
            compose.pressBack()
            compose.tap("connect")
            compose.waitForTag("username")
            compose.replaceText("username", "qa")
            compose.replaceText("password", "qa")
            compose.pressBack()
            compose.tap("sign-in")
            compose.waitForTag("library-home", 20_000)
            compose.waitForTag("shelf-item-book-0")
            compose.onAllNodesWithTag("shelf-item-book-0")[0].performClick()
            compose.tap("download")
            compose.waitForTag("download-retry", 45_000)
            val failed = saved()!!
            assertEquals(DownloadStore.State.FAILED, failed.state)
            assertEquals(2, failed.parts.count { it.done })
            retained = failed.parts.filter { it.done }.associate { it.name to digest(File(failed.directory, it.name)) }
            assertEquals(2, audioRequests())
            val bodyBefore = JSONObject(Fixture.get("${Fixture.server}/__android__/download-control"))
            control("body")
            compose.onNodeWithTag("download-retry").performScrollTo().performClick()
            eventually(15_000) {
                JSONObject(Fixture.get("${Fixture.server}/__android__/download-control")).getInt("bodyStarted") > bodyBefore.getInt("bodyStarted") &&
                    File(failed.directory, "ebook.pdf.part").length() == 512L
            }
            compose.onNodeWithTag("download-cancel").performScrollTo().performClick()
            val cancelled = saved()
            assertNotNull("Cancel must retain the persisted download and completed audio", cancelled)
            assertEquals("Cancelled work must remain retryable", DownloadStore.State.FAILED, cancelled!!.state)
            retained.forEach { (name, hash) -> assertEquals(hash, digest(File(cancelled.directory, name))) }
            control("normal")
            compose.onNodeWithTag("download-retry").performScrollTo().performClick()
            assertTrue("Cancel must close the active response body before its withheld tail is released", runCatching {
                eventually(5_000) { JSONObject(Fixture.get("${Fixture.server}/__android__/download-control")).getInt("bodyClosed") > bodyBefore.getInt("bodyClosed") }
            }.isSuccess)
            compose.pressBack()
            compose.tap("tab-downloads")
            compose.waitForTag("offline-book-0", 45_000)
            val complete = saved()!!
            assertEquals(DownloadStore.State.COMPLETE, complete.state)
            assertTrue(complete.parts.all { it.done })
            retained.forEach { (name, hash) -> assertEquals(hash, digest(File(complete.directory, name))) }
            assertEquals("Retry must not fetch completed audio again", 2, audioRequests())
            val expectedPdf = JSONObject(Fixture.get("${Fixture.server}/__android__/download-control")).getString("pdfSha256")
            assertEquals(expectedPdf, MessageDigest.getInstance("SHA-256").digest(File(complete.directory, "ebook.pdf").readBytes()).joinToString("") { "%02x".format(it) })
            control("release")
            eventually(5_000) { JSONObject(Fixture.get("${Fixture.server}/__android__/download-control")).getInt("bodyEnded") > bodyBefore.getInt("bodyEnded") }
            assertEquals(DownloadStore.State.COMPLETE, saved()!!.state)
            assertFalse("The stopped body must not recreate staging", File(complete.directory, "ebook.pdf.part").exists())
            assertEquals(expectedPdf, MessageDigest.getInstance("SHA-256").digest(File(complete.directory, "ebook.pdf").readBytes()).joinToString("") { "%02x".format(it) })
        }
        Fixture.configure("offline-library")
        val offlineStart = Fixture.requests().size
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("tab-downloads")
            compose.tap("play-offline-book-0")
            compose.waitForTag("mini-playing", 10_000)
            compose.tap("mini-player")
            compose.waitForText("Next chapter")
            compose.closePlayer()
            compose.tap("read-offline-book-0")
            compose.waitForTag("pdf-document", 10_000)
            assertEquals(2, audioRequests())
            assertFalse("Offline content must use retained files", Fixture.requests().drop(offlineStart).any {
                it.getString("path").startsWith("/api/items/book-0/file/") || it.getString("path").startsWith("/api/items/book-0/play")
            })
        }
    }
}
