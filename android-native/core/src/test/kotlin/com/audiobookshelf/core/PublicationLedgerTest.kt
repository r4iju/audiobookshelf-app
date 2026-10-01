package com.audiobookshelf.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException

class PublicationLedgerTest {
    @get:Rule val folder = TemporaryFolder()
    private val qa = AccountIdentity("http://127.0.0.1:28765/abs", "u1")
    private val other = AccountIdentity("http://127.0.0.1:28765/abs", "u2")
    private val book0 = PublicationLedger.Title("book-0", null)
    private val book1 = PublicationLedger.Title("book-1", null)
    private val file get() = folder.root.resolve("publications.json")

    private fun fail(failure: Exception) = runBlocking {
        runCatching { PublicationLedger(file).publish(qa, PublicationLedger.Kind.READING, listOf(book0)) { throw failure } }
        PublicationLedger(file)
    }

    @Test
    fun onlyAWriteThatMayStillBeAppliedHoldsItsTitle() {
        assertTrue("A lost answer", fail(ApiError.Offline(SocketTimeoutException())).uncertain(qa, "book-0", null))
        folder.delete(); folder.create()
        assertTrue("A gateway that gave up waiting", fail(ApiError.Http(504)).uncertain(qa, "book-0", null))
        folder.delete(); folder.create()
        assertTrue("A proxy whose upstream connection reset after forwarding", fail(ApiError.Http(503)).uncertain(qa, "book-0", null))
        folder.delete(); folder.create()
        assertFalse("The server answered, so its handler is done", fail(ApiError.Http(500)).uncertain(qa, "book-0", null))
        folder.delete(); folder.create()
        assertFalse("Never sent", fail(ApiError.Offline(ConnectException())).uncertain(qa, "book-0", null))
    }

    @Test
    fun aWriteInterruptedByProcessDeathIsUncertainAfterRestart() = runBlocking {
        val ledger = PublicationLedger(file)
        var reopened: PublicationLedger? = null
        ledger.publish(qa, PublicationLedger.Kind.LISTENING, listOf(book0)) { reopened = PublicationLedger(file) }
        assertTrue("Issued before sending, so a restart finds it", reopened!!.uncertain(qa, "book-0", null))
        assertFalse("This answer settles it", PublicationLedger(file).uncertain(qa, "book-0", null))
    }

    @Test
    fun uncertaintyIsPerTitleAndAccountAndEndsOnlyByTheUsersChoice() = runBlocking {
        val ledger = PublicationLedger(file)
        runCatching { ledger.publish(qa, PublicationLedger.Kind.LISTENING, listOf(book0, book1)) { throw IOException("reset") } }
        // A later write of the same title that is answered does not settle the earlier one.
        ledger.publish(qa, PublicationLedger.Kind.LISTENING, listOf(book0)) { }
        assertTrue(ledger.uncertain(qa, "book-0", null))
        assertFalse(ledger.uncertain(other, "book-0", null))
        assertFalse(ledger.uncertain(qa, "book-2", null))

        ledger.accept(qa, "book-0", null)
        val reopened = PublicationLedger(file)
        assertFalse(reopened.uncertain(qa, "book-0", null))
        assertTrue("Other titles of the write stay uncertain", reopened.uncertain(qa, "book-1", null))
    }

    @Test
    fun aListeningWriteKeepsWhatWasSent() = runBlocking {
        val journal = ListeningJournal(folder.root.resolve("journal.json"))
        val id = journal.begin(qa, ListeningMedia("book-0", null, "Stories", "QA", "book", 20.0, 6.0), "device", now = 1_000)
        journal.record(id, 9.0, 3.0, now = 2_000)
        val sent = journal.pending(qa)
        runCatching { PublicationLedger(file).publish(qa, PublicationLedger.Kind.LISTENING, listOf(book0), sent) { throw IOException("reset") } }
        assertEquals(sent, PublicationLedger(file).attempts.value.single().listening)
    }

    @Test
    fun unreadableRecordsHoldEveryTitleAndAreNeitherDiscardedNorOverwritten() = runBlocking {
        file.writeText("{\"version\":1,\"attempts\":[{\"id\"")
        val ledger = PublicationLedger(file)
        assertTrue(ledger.uncertain(qa, "book-7", null))
        assertThrows(PublicationLedger.Unreadable::class.java) { runBlocking { ledger.publish(qa, PublicationLedger.Kind.READING, listOf(book0)) { } } }
        assertEquals("{\"version\":1,\"attempts\":[{\"id\"", file.readText())

        ledger.setAsideUnreadable(now = 5)
        assertFalse(ledger.uncertain(qa, "book-7", null))
        assertTrue(folder.root.resolve("publications.json.unreadable-5").exists())
    }
}
