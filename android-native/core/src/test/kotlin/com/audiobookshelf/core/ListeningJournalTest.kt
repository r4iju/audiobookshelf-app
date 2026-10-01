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
}
