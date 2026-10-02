package com.audiobookshelf.android.reader

import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.MediaProgress
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class ReadingSyncTest {
    private val account = AccountIdentity("https://abs.example", "u1")

    /** One server's reading progress for the book, changed by this device or by others. */
    private class Server : ReadingRemote {
        var location: String? = null
        var updatedAt = 0.0
        val saved = mutableListOf<String>()
        var reads = 0

        fun otherDeviceReads(page: Int, at: Double) { location = "$page"; updatedAt = at }

        override suspend fun progress(itemId: String): MediaProgress? {
            // Bounds a publication that would otherwise ask again forever.
            check(++reads <= 20) { "The server was asked $reads times" }
            return location?.let { MediaProgress(libraryItemId = itemId, ebookLocation = it, ebookProgress = 0.0, lastUpdate = updatedAt) }
        }

        override suspend fun save(itemId: String, location: String, progress: Double) {
            saved += location
            this.location = location
            updatedAt += 1_000
        }
    }

    private fun store() = ReadingStore(File(Files.createTempDirectory("reading").toFile(), "reading-positions.json"))
    private fun sync(store: ReadingStore, server: Server) =
        ReadingSync(CoroutineScope(Dispatchers.Unconfined), store, remoteFor = { server }, onSignInRequired = {})

    @Test
    fun anotherDevicesNewerPageIsNeverOverwrittenByAPendingLocalPage() = runBlocking {
        val store = store(); val server = Server()
        server.otherDeviceReads(page = 1, at = 1_000.0)
        store.adoptRemote(account, "book", PRIMARY, server.progress("book"))
        store.record(account, "book", PRIMARY, primary = true, page = 3, pages = 10)
        server.otherDeviceReads(page = 7, at = 5_000.0)

        sync(store, server).publish(account)

        assertTrue("The other device's page must not be overwritten: ${server.saved}", server.saved.isEmpty())
        assertEquals("7", server.location)
        val entry = store.entry(account, "book", PRIMARY)!!
        assertEquals("The local page is kept for the reader to decide", 3, entry.page)
        assertEquals(7, entry.conflictPage)
    }

    @Test
    fun aNewerRemotePageSeenWhileALocalPageIsPendingIsKeptAsAConflict() {
        val store = store()
        store.adoptRemote(account, "book", PRIMARY, MediaProgress(libraryItemId = "book", ebookLocation = "1", lastUpdate = 1_000.0))
        store.record(account, "book", PRIMARY, primary = true, page = 3, pages = 10)
        store.adoptRemote(account, "book", PRIMARY, MediaProgress(libraryItemId = "book", ebookLocation = "7", lastUpdate = 5_000.0))
        val entry = store.entry(account, "book", PRIMARY)!!
        assertEquals(3, entry.page)
        assertEquals(7, entry.conflictPage)
        assertFalse("A conflict is not published until resolved", store.publishable(account).any())
    }

    @Test
    fun choosingTheLocalPagePublishesItAndChoosingTheRemotePageAdoptsIt() = runBlocking {
        val server = Server()
        for (keepLocal in listOf(true, false)) {
            val store = store()
            server.otherDeviceReads(page = 1, at = 1_000.0); server.saved.clear()
            store.adoptRemote(account, "book", PRIMARY, server.progress("book"))
            store.record(account, "book", PRIMARY, primary = true, page = 3, pages = 10)
            server.otherDeviceReads(page = 7, at = 5_000.0)
            sync(store, server).publish(account)
            store.resolveConflict(account, "book", PRIMARY, keepLocal = keepLocal)
            sync(store, server).publish(account)
            val entry = store.entry(account, "book", PRIMARY)!!
            assertNull(entry.conflictPage)
            assertFalse(entry.pending)
            if (keepLocal) { assertEquals(listOf("3"), server.saved); assertEquals(3, entry.page) }
            else { assertTrue(server.saved.isEmpty()); assertEquals(7, entry.page); assertEquals("7", server.location) }
        }
    }

    @Test
    fun aNewerPositionThatIsNotAPageWaitsForTheReaderWithoutAskingTheServerAgain() = runBlocking {
        val store = store(); val server = Server()
        server.otherDeviceReads(page = 1, at = 1_000.0)
        store.adoptRemote(account, "book", PRIMARY, server.progress("book"))
        store.record(account, "book", PRIMARY, primary = true, page = 3, pages = 10)
        // Another client saved a position this reader cannot show as a page.
        server.location = "epubcfi(/6/4!/4/2/1:0)"; server.updatedAt = 5_000.0
        server.reads = 0

        sync(store, server).publish(account)

        assertEquals("One look at the server decides; it is not asked again", 1, server.reads)
        assertTrue("The other position must not be overwritten: ${server.saved}", server.saved.isEmpty())
        assertFalse("The page waits for the reader instead of being retried", store.publishable(account).any())
        store.resolveConflict(account, "book", PRIMARY, keepLocal = true)
        sync(store, server).publish(account)
        assertEquals("Keeping this device's page publishes it", listOf("3"), server.saved)
    }

    private companion object { const val PRIMARY = "primary" }
}
