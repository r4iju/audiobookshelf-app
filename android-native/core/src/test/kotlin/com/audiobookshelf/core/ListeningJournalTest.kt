package com.audiobookshelf.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ListeningJournalTest {
    @get:Rule val folder = TemporaryFolder()
    private val qa = AccountIdentity("http://127.0.0.1:28765/abs", "u1")
    private val other = AccountIdentity("http://127.0.0.1:28765/abs", "u2")
    private val book = ListeningMedia("book-0", null, "Stories", "QA", "book", 20.0, 6.0)

    @Test
    fun unsentListeningSurvivesReopeningAndStaysAccountScoped() {
        val file = folder.root.resolve("journal.json")
        val journal = ListeningJournal(file)
        val id = journal.begin(qa, book, "device", now = 1_000)
        journal.record(id, position = 9.5, listened = 3.5, now = 2_000)
        journal.begin(other, book, "device", now = 1_500)

        val reopened = ListeningJournal(file)
        val pending = reopened.pending(qa).single()
        assertEquals(id, pending.id)
        assertEquals(9.5, pending.currentTime, 0.0)
        assertEquals(3.5, pending.timeListening, 0.0)
        assertEquals(2_000.0, pending.updatedAt, 0.0)
        assertEquals(1, reopened.pending(other).size)
        assertEquals(9.5, reopened.cachedPosition(qa, "book-0", null, newerThan = 0.0)!!, 0.0)
    }

    @Test
    fun acknowledgmentRetiresOnlyTheRevisionThatWasSent() {
        val journal = ListeningJournal(folder.root.resolve("journal.json"))
        val id = journal.begin(qa, book, "device", now = 1_000)
        journal.record(id, 8.0, 2.0, now = 2_000)
        val sent = journal.pending(qa).single()
        journal.record(id, 10.0, 2.0, now = 3_000)
        journal.acknowledge(sent)

        val remaining = journal.pending(qa).single()
        assertEquals(4.0, remaining.timeListening, 0.0)
        journal.finish(id)
        journal.acknowledge(remaining)
        assertTrue(journal.pending(qa).isEmpty())
        assertEquals(10.0, journal.cachedPosition(qa, "book-0", null, 0.0)!!, 0.0)
    }

    @Test
    fun newerRemotePositionWinsOverOlderLocalCache() {
        val journal = ListeningJournal(folder.root.resolve("journal.json"))
        val id = journal.begin(qa, book, "device", now = 1_000)
        journal.record(id, 12.0, 6.0, now = 2_000)
        journal.rememberRemotePosition(qa, "book-0", null, time = 3.0, updatedAt = 5_000.0)
        assertEquals(3.0, journal.cachedPosition(qa, "book-0", null, 0.0)!!, 0.0)
        assertNull(journal.cachedPosition(qa, "book-0", null, newerThan = 6_000.0))
    }

    @Test
    fun unreadableJournalIsPreservedForRecovery() {
        val file = folder.root.resolve("journal.json")
        val damaged = "{\"version\":1,\"records\":[{".toByteArray()
        file.writeBytes(damaged)
        assertThrows(ListeningJournal.Unreadable::class.java) { ListeningJournal(file) }
        assertArrayEquals(damaged, file.readBytes())
    }

    @Test
    fun aResetOutranksServerSnapshotsTakenBeforeIt() {
        val file = folder.root.resolve("journal.json")
        val journal = ListeningJournal(file)
        val id = journal.begin(qa, book, "device", now = 1_000)
        journal.record(id, position = 9.5, listened = 3.5, now = 2_000)
        journal.resetPosition(qa, "book-0", null, at = 5_000.0)

        val reopened = ListeningJournal(file)
        reopened.adoptRemotePosition(qa, "book-0", null, time = 9.5, updatedAt = 3_000.0)
        assertEquals(0.0, reopened.cachedPosition(qa, "book-0", null, newerThan = Double.NEGATIVE_INFINITY)!!, 0.0)
        assertEquals(0.0, reopened.cachedPosition(qa, "book-0", null, newerThan = 4_000.0)!!, 0.0)

        reopened.adoptRemotePosition(qa, "book-0", null, time = 2.0, updatedAt = 6_000.0)
        assertEquals(2.0, reopened.cachedPosition(qa, "book-0", null, newerThan = Double.NEGATIVE_INFINITY)!!, 0.0)
    }

    @Test
    fun listeningAfterAWriteWithoutAnAnswerGoesToANewSessionAndTheSentOneIsResentUnchanged() {
        val file = folder.root.resolve("journal.json")
        val journal = ListeningJournal(file)
        val id = journal.begin(qa, book, "device", now = 1_000)
        journal.record(id, 10.0, 4.0, now = 2_000)
        val sent = journal.pending(qa).single()
        journal.freeze(sent)
        journal.record(id, 13.0, 3.0, now = 3_000)

        val pending = ListeningJournal(file).pending(qa)
        assertEquals("The unanswered write is resent exactly as it was", sent.payload(), pending.single { it.id == sent.id }.payload())
        val later = pending.single { it.id != sent.id }
        assertEquals("Only listening after it, so the server never counts it twice", 3.0, later.timeListening, 0.0)
        assertEquals(13.0, later.currentTime, 0.0)
        assertEquals(10.0, later.media.startTime, 0.0)

        journal.finish(id)
        journal.acknowledge(pending.single { it.id == sent.id })
        journal.acknowledge(later)
        assertTrue(journal.pending(qa).isEmpty())
        // Freezing again, as after a restart, changes nothing.
        journal.freeze(sent)
        assertTrue(journal.pending(qa).isEmpty())
    }
}
