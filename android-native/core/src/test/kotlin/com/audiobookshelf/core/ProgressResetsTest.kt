package com.audiobookshelf.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

class ProgressResetsTest {
    @get:Rule val folder = TemporaryFolder()
    private val qa = AccountIdentity("http://127.0.0.1:28765/abs", "u1")
    private val other = AccountIdentity("http://127.0.0.1:28765/abs", "u2")

    private class Server(vararg progress: MediaProgress) : ProgressRemote {
        val progress = progress.toMutableList()
        val removed = mutableListOf<String>()
        var loseNextRemoveResponse = false
        override suspend fun progress(itemId: String, episodeId: String?) = progress.firstOrNull { it.libraryItemId == itemId && it.episodeId == episodeId }
        override suspend fun remove(progressId: String) {
            if (progress.none { it.id == progressId }) throw ApiError.Http(404)
            progress.removeAll { it.id == progressId }
            removed += progressId
            if (loseNextRemoveResponse) { loseNextRemoveResponse = false; throw IOException("connection reset") }
        }
    }

    private fun resets(servers: Map<AccountIdentity, Server>, cleaned: MutableList<Pair<ProgressResets.Reset, Double>> = mutableListOf(), cleanup: (ProgressResets.Reset, Double) -> Unit = { reset, at -> cleaned += reset to at }) =
        ProgressResets(folder.root.resolve("resets.json"), remoteFor = { servers[it] }, exclusive = { _, block -> block(); true }, cleanup = cleanup)

    @Test
    fun aRequestedResetSurvivesRelaunchAndCompletesForItsOwnAccountOnly() = runBlocking {
        val mine = Server(MediaProgress(id = "p1", libraryItemId = "book-0", currentTime = 10.0, lastUpdate = 2_000.0))
        val theirs = Server(MediaProgress(id = "p9", libraryItemId = "book-0", currentTime = 4.0, lastUpdate = 2_000.0))
        resets(emptyMap()).request(qa, "book-0", null, now = 5_000)

        // The app restarts while the account is signed out, then another account on the same server signs in.
        val cleaned = mutableListOf<Pair<ProgressResets.Reset, Double>>()
        val relaunched = resets(mapOf(other to theirs), cleaned)
        assertTrue("A requested reset must survive a restart", relaunched.pending(qa, "book-0", null))
        relaunched.complete(other)
        assertEquals(listOf<String>(), theirs.removed)

        val back = resets(mapOf(qa to mine, other to theirs), cleaned)
        assertTrue(back.complete(qa))
        assertEquals(listOf("p1"), mine.removed)
        assertEquals(listOf<String>(), theirs.removed)
        assertFalse(back.pending(qa, "book-0", null))
        assertEquals(1, cleaned.size)
    }

    @Test
    fun localCleanupThatFailsLeavesTheServerProgressAndTheRequest() = runBlocking {
        val server = Server(MediaProgress(id = "p1", libraryItemId = "book-0", currentTime = 10.0, lastUpdate = 2_000.0))
        var storageWorks = false
        val resets = resets(mapOf(qa to server), cleanup = { _, _ -> if (!storageWorks) throw IOException("disk full") })
        resets.request(qa, "book-0", null, now = 5_000)

        runCatching { resets.complete(qa) }
        assertEquals("Server progress must stay until this device has durably forgotten the title", listOf<String>(), server.removed)
        assertTrue(resets.pending(qa, "book-0", null))

        storageWorks = true
        assertTrue(resets.complete(qa))
        assertEquals(listOf("p1"), server.removed)
    }

    @Test
    fun aResetWhoseDeleteResponseWasLostDoesNotDeleteProgressMadeAfterIt() = runBlocking {
        val server = Server(MediaProgress(id = "p1", libraryItemId = "book-0", currentTime = 10.0, lastUpdate = 2_000.0))
        server.loseNextRemoveResponse = true
        val resets = resets(mapOf(qa to server))
        resets.request(qa, "book-0", null, now = 5_000)
        runCatching { resets.complete(qa) }

        // Another device starts the title again before this one learns its delete succeeded.
        server.progress += MediaProgress(id = "p2", libraryItemId = "book-0", currentTime = 3.0, lastUpdate = 9_000.0)
        assertTrue(resets.complete(qa))
        assertEquals(listOf("p1"), server.removed)
        assertEquals(listOf("p2"), server.progress.map { it.id })
    }

    @Test
    fun theDeviceForgetsTheTitleAsOfTheLatestServerUpdateItSawBeforeDeleting() = runBlocking {
        // The server clock is ahead of this device; a snapshot from before the delete must still be older than the reset.
        val server = Server(MediaProgress(id = "p1", libraryItemId = "book-0", currentTime = 10.0, lastUpdate = 8_000.0))
        val cleaned = mutableListOf<Pair<ProgressResets.Reset, Double>>()
        val resets = resets(mapOf(qa to server), cleaned)
        resets.request(qa, "book-0", null, now = 5_000)
        assertTrue(resets.complete(qa))
        assertTrue("Reset at ${cleaned.single().second}", cleaned.single().second >= 8_000.0)
    }

    @Test
    fun unreadableResetsHoldEveryTitleAndAreNeitherDiscardedNorOverwritten() = runBlocking {
        val file = folder.root.resolve("resets.json")
        file.writeText("{\"version\":1,\"resets\":[{\"account\"")
        val server = Server(MediaProgress(id = "p1", libraryItemId = "book-0", currentTime = 10.0, lastUpdate = 2_000.0))
        val resets = resets(mapOf(qa to server))

        assertTrue("An unreadable reset may be for any title", resets.pending(qa, "book-0", null))
        assertTrue(resets.pending(other, "book-9", "episode"))
        runCatching { resets.request(qa, "book-1", null) }
        assertFalse(resets.complete(qa))
        assertEquals(listOf<String>(), server.removed)
        assertEquals("{\"version\":1,\"resets\":[{\"account\"", file.readText())

        // A restart reads the same file and still holds every title.
        assertTrue(resets(mapOf(qa to server)).pending(qa, "book-0", null))
    }
}
