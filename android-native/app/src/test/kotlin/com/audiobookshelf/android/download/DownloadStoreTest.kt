package com.audiobookshelf.android.download

import com.audiobookshelf.core.AccountIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DownloadStoreTest {
    private fun record(id: String) = DownloadStore.Record(
        id = id, account = AccountIdentity("https://abs.example", "u1"), itemId = id, title = id, mediaType = "book",
        parts = listOf(DownloadStore.Part("/api/items/$id/file/0", "0.mp3")), directory = "downloads/$id",
    )

    @Test
    fun aManifestThatCannotBeReplacedIsNotReportedAsSaved() {
        val directory = Files.createTempDirectory("downloads").toFile()
        val manifest = File(directory, "downloads.json")
        val store = DownloadStore(manifest)
        store.put(record("kept"))
        val saved = manifest.readText()

        // A replacement the file system refuses: the manifest's place is taken by something rename cannot overwrite.
        manifest.delete()
        File(manifest, "occupied").apply { parentFile.mkdirs(); writeText(saved) }

        val attempt = runCatching { store.put(record("lost")) }
        assertTrue("A refused replacement must fail the save", attempt.isFailure)
        assertEquals("Only durable records are published", listOf("kept"), store.records.value.map { it.id })
        assertEquals("What was on disk stays", saved, File(manifest, "occupied").readText())
    }
}
