package com.audiobookshelf.android.podcast

import com.audiobookshelf.core.AccountIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class PodcastRequestsTest {
    @Test
    fun unreadableQueueIsNeverOverwritten() {
        val file = Files.createTempFile("podcast-requests", ".json").toFile()
        file.writeText("{not json")
        val requests = PodcastRequests(file)
        assertFalse(requests.writable)
        val attempt = runCatching { requests.begin(AccountIdentity("https://abs.example", "u1"), "podcast", listOf("Episode" to "https://feed.example/1.mp3")) }
        assertTrue(attempt.isFailure)
        assertEquals("{not json", file.readText())
    }
}
