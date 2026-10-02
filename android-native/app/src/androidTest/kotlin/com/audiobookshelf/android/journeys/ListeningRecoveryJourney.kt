package com.audiobookshelf.android.journeys

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.AppGraph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ListeningJournal
import com.audiobookshelf.core.ListeningMedia
import com.audiobookshelf.core.PublicationLedger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Relaunch after process death while a listening write was out, on a device whose storage refuses writes. */
@RunWith(AndroidJUnit4::class)
class ListeningRecoveryJourney {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val root = File(instrumentation.targetContext.cacheDir, "listening-recovery")
    private val files = File(root, "files")
    private val account = AccountIdentity("http://127.0.0.1:28765", "u1")
    private val media = ListeningMedia("book-0", null, "Stories", "QA", "book", 20.0, 6.0)

    /** The app as relaunched, keeping its files in [files]. */
    private fun relaunched(): AppGraph = AppGraph(object : ContextWrapper(instrumentation.targetContext.applicationContext) {
        override fun getFilesDir() = files
        override fun getNoBackupFilesDir() = File(root, "no-backup").apply { mkdirs() }
        override fun getApplicationContext(): Context = this
    })

    private fun local() = PlaySource.Local(account, "book-0", null, "Stories", "QA", null, "book", emptyList(), emptyList(), emptyList(), 0.0)

    private fun refusal(graph: AppGraph): String? {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            graph.playback.state.value.openError?.let { return it.second }
            Thread.sleep(100)
        }
        return null
    }

    @After fun restore() {
        files.setWritable(true)
        root.deleteRecursively()
    }

    @Test
    fun listeningOutAtProcessDeathWaitsForStorageAndIsThenKeptAsSent() {
        root.deleteRecursively()
        files.mkdirs()
        File(files, "device-id").writeText("recovery-device")
        val journalFile = File(files, "listening-journal.json")
        val journal = ListeningJournal(journalFile)
        val id = journal.begin(account, media, "recovery-device", now = 1_000)
        journal.record(id, 10.0, 4.0, now = 2_000)
        val sent = journal.pending(account).single()
        val ledger = PublicationLedger(File(files, "publication-ledger.json"))
        // The process ends while the write is out, after more listening was journaled.
        runCatching { runBlocking { ledger.publish(account, PublicationLedger.Kind.LISTENING, listOf(PublicationLedger.Title("book-0", null)), listOf(sent)) { throw java.io.IOException("process ended") } } }
        journal.record(id, 13.0, 3.0, now = 3_000)
        val before = journalFile.readText()

        assertTrue(files.setWritable(false))
        val graph = relaunched()
        instrumentation.runOnMainSync { graph.playback.play(local()) }
        val refused = refusal(graph)
        assertTrue("Nothing plays while listening from before cannot be kept as sent: $refused", refused?.contains("storage") == true)
        assertEquals("The journal is untouched", before, journalFile.readText())
        assertTrue("The record of the unanswered write is kept", PublicationLedger(File(files, "publication-ledger.json")).uncertain(account, "book-0", null))

        // Storage recovers and the user tries again.
        assertTrue(files.setWritable(true))
        instrumentation.runOnMainSync { graph.playback.play(local()) }
        val deadline = System.currentTimeMillis() + 10_000
        while (journalFile.readText() == before && System.currentTimeMillis() < deadline) Thread.sleep(100)
        val pending = ListeningJournal(journalFile).pending(account)
        assertEquals("The session is sent again only as it was", sent.payload(), pending.single { it.id == sent.id }.payload())
        assertEquals("Later listening goes to a new session", 3.0, pending.single { it.id != sent.id }.timeListening, 0.0)
    }
}
