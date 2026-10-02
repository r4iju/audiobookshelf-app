package com.audiobookshelf.app.migration

import android.content.Context
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.app.data.*
import com.audiobookshelf.app.managers.DbManager
import com.audiobookshelf.app.models.DownloadItem
import com.audiobookshelf.app.models.DownloadItemPart
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import io.paperdb.Paper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.zip.ZipFile

/**
 * A synthetic legacy installation, written through the legacy app's own classes and Paper books,
 * exported for the new app. Every secret is a `SYNTHETIC-` marker that must not leave the device.
 */
@RunWith(AndroidJUnit4::class)
class LegacyMigrationExportTest {
  private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
  private val db = DbManager()
  private val server = "http://127.0.0.1:28765/abs"
  private val qa = "00000000-0000-4000-8000-000000000001"
  private val other = "00000000-0000-4000-8000-000000000002"
  private val downloads get() = File(context.filesDir, "downloads")

  /** Silent 16-bit mono WAV, as the fixture server serves. */
  private fun wav(seconds: Int): ByteArray {
    val rate = 8000
    val data = seconds * rate * 2
    return ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN).apply {
      put("RIFF".toByteArray()); putInt(36 + data); put("WAVE".toByteArray())
      put("fmt ".toByteArray()); putInt(16); putShort(1); putShort(1); putInt(rate); putInt(rate * 2); putShort(2); putShort(16)
      put("data".toByteArray()); putInt(data)
    }.array()
  }

  private fun pdf(pages: Int): ByteArray {
    val document = PdfDocument()
    repeat(pages) { index ->
      val page = document.startPage(PdfDocument.PageInfo.Builder(300, 400, index + 1).create())
      page.canvas.drawText("Page ${index + 1}", 40f, 60f, android.graphics.Paint().apply { textSize = 24f })
      document.finishPage(page)
    }
    return ByteArrayOutputStream().also { document.writeTo(it); document.close() }.toByteArray()
  }

  private fun place(itemId: String, name: String, bytes: ByteArray, mimeType: String): LocalFile {
    val file = File(downloads, "$itemId/$name").apply { parentFile!!.mkdirs(); writeBytes(bytes) }
    return LocalFile("file-$itemId-$name", name, Uri.fromFile(file).toString(), file.parent!!, file.absolutePath, mimeType, bytes.size.toLong())
  }

  private fun track(index: Int, offset: Double, duration: Double, file: LocalFile) =
    AudioTrack(index, offset, duration, file.filename!!, file.contentUrl, file.mimeType, null, true, file.id, index)

  private val internalBooks = LocalFolder("internal-book", "Internal App Storage", "", "", "", "internal-app", "book")

  private fun book(id: String, title: String, files: List<LocalFile>, tracks: List<AudioTrack>, ebook: EBookFile?, userId: String = qa, connection: String = "conn-qa") =
    LocalLibraryItem(
      "local_$id", internalBooks.id, File(downloads, id).absolutePath, File(downloads, id).absolutePath, Uri.fromFile(File(downloads, id)).toString(), false, "book",
      Book(BookMetadata(title, null, mutableListOf(Author("author", "Audiobookshelf QA", null)), mutableListOf(), mutableListOf(), null, null, null, null, null, null, null, false, "Audiobookshelf QA", null, null, null, null),
        null, listOf(), null, listOf(BookChapter(0, 0.0, 8.0, "Opening"), BookChapter(1, 8.0, 20.0, "Next chapter")), tracks.toMutableList(), ebook, files.sumOf { it.size }, tracks.sumOf { it.duration }, tracks.size),
      files.toMutableList(), null, null, true, connection, server, userId, id,
    )

  private fun seed() {
    DbManager.initialize(context)
    listOf("device", "localLibraryItems", "localFolders", "downloadItems", "localMediaProgress", "playbackSession", "mediaItemHistory").forEach { Paper.book(it).destroy() }
    downloads.deleteRecursively()

    db.saveDeviceData(DeviceData(
      mutableListOf(
        ServerConnectionConfig("conn-qa", 0, "QA shelf", server, "2.30.0", qa, "qa", "SYNTHETIC-ACCESS-TOKEN", mapOf("X-Synthetic" to "SYNTHETIC-HEADER")),
        ServerConnectionConfig("conn-elsewhere", 1, "Elsewhere", "https://elsewhere.invalid", "2.30.0", "user-elsewhere", "reader", "SYNTHETIC-OTHER-TOKEN", null),
      ),
      "conn-qa",
      DeviceSettings.default().apply { jumpForwardTime = 30; jumpBackwardsTime = 5; disableAutoRewind = true; androidAutoBrowseLimitForGrouping = 50 },
      null,
    ))
    context.getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE).edit()
      .putString("userSettings", """{"playbackRate":1.5,"mobileOrderBy":"addedAt"}""")
      .putString("serverSettings", """{"SYNTHETIC":"cache"}""")
      .putString("bookshelfListView", "1")
      .putString("theme", "dark")
      .putString("lastLibraryId", "books")
      .putString("device", """{"token":"SYNTHETIC-DEVICE-TOKEN"}""")
      .commit()
    context.getSharedPreferences("SecureStorage", Context.MODE_PRIVATE).edit().putString("refresh_token_conn-qa", "SYNTHETIC-REFRESH-TOKEN").commit()

    val first = place("book-0", "track-1.wav", wav(8), "audio/wav")
    val second = place("book-0", "track-2.wav", wav(12), "audio/wav")
    val pdf = place("book-0", "stories.pdf", pdf(4), "application/pdf")
    db.saveLocalLibraryItem(book("book-0", "Stories for Tomorrow 01", listOf(first, second, pdf),
      listOf(track(0, 0.0, 8.0, first), track(1, 8.0, 12.0, second)), EBookFile("pdf", null, "pdf", true, pdf.id, pdf.contentUrl)))

    // A deferred format keeps its file and location without conversion.
    val epub = place("book-1", "stories.epub", "SYNTHETIC EPUB BYTES".toByteArray(), "application/epub+zip")
    db.saveLocalLibraryItem(book("book-1", "Stories for Tomorrow 02", listOf(epub), listOf(), EBookFile("epub", null, "epub", true, epub.id, epub.contentUrl)))

    // Recorded for another user under this connection: kept, never attached automatically.
    val foreign = place("book-2", "track-1.wav", wav(2), "audio/wav")
    db.saveLocalLibraryItem(book("book-2", "Stories for Tomorrow 03", listOf(foreign), listOf(track(0, 0.0, 2.0, foreign)), null, userId = other))

    // The file was removed by a file manager; the legacy record still lists it.
    val gone = place("book-3", "track-1.wav", wav(1), "audio/wav").also { File(it.absolutePath).delete() }
    db.saveLocalLibraryItem(book("book-3", "Stories for Tomorrow 04", listOf(gone), listOf(track(0, 0.0, 1.0, gone)), null))

    db.saveLocalMediaProgress(LocalMediaProgress("local_book-0", "local_book-0", null, 20.0, 0.475, 9.5, false, "2", 0.25, 1_790_000_000_000, 1_789_000_000_000, null, "conn-qa", server, qa, "book-0", null))
    db.saveLocalMediaProgress(LocalMediaProgress("local_book-1", "local_book-1", null, 0.0, 0.0, 0.0, false, "epubcfi(/6/4!/4/2/1:0)", 0.4, 1_790_000_000_000, 1_789_000_000_000, null, "conn-qa", server, qa, "book-1", null))

    db.savePlaybackSession(PlaybackSession(
      "legacy-session-1", qa, "book-0", null, "book", BookMetadata("Stories for Tomorrow 01", null, null, null, mutableListOf(), null, null, null, null, null, null, null, false, "Audiobookshelf QA", null, null, null, null),
      DeviceInfo("SYNTHETIC-ANDROID-ID", "QA", "Emulator", 36, "0.14.2-beta"), listOf(), "Stories for Tomorrow 01", "Audiobookshelf QA", null, 20.0, 3,
      1_790_000_000_000 - 7_000, 1_790_000_000_000, 7, mutableListOf(), 9.5, null, null, null, "conn-qa", server, "exo-player",
    ))

    db.saveMediaItemHistory(MediaItemHistory("local_book-0", "Stories for Tomorrow 01", "book-0", null, false,
      "conn-qa", server, qa, 1_790_000_000_000, mutableListOf(
        MediaItemEvent("Seek", "Playback", "", 9.5, false, null, null, 1_790_000_000_000))))

    // A download still running when the legacy app last ran: one part finished and moved.
    val partial = place("book-4", "track-1.wav", wav(8), "audio/wav")
    val unfinished = File(downloads, "book-4/track-2.wav")
    // The legacy downloader keeps the server's track, with its 1-based index.
    fun part(file: File, index: Int, done: Boolean, size: Long) = DownloadItemPart(
      "part-${file.name}", "book-4", file.name, size, file.absolutePath, file.absolutePath, "/api/items/book-4/file/${index - 1}/download", internalBooks.name, "", internalBooks.id,
      null, AudioTrack(index, if (index == 1) 0.0 else 8.0, if (index == 1) 8.0 else 12.0, file.name, "/api/items/book-4/file/${index - 1}", "audio/wav", null, false, null, null), null, done, done, false, false, Uri.parse("$server/api/items/book-4/file?token=SYNTHETIC-QUERY-TOKEN"), Uri.fromFile(file), Uri.fromFile(file), null, "", null, null, 0, 0)
    db.saveDownloadItem(DownloadItem("book-4", "book-4", null, null, "conn-qa", server, qa, "book", File(downloads, "book-4").absolutePath, internalBooks, "Stories for Tomorrow 05", "Audiobookshelf QA/Stories for Tomorrow 05",
      book("book-4", "Stories for Tomorrow 05", listOf(), listOf(), null).media, mutableListOf(part(File(partial.absolutePath), 1, true, partial.size), part(unfinished, 2, false, 192_044))))
  }

  private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

  @Before fun prepare() = seed()

  @Test
  fun aLegacyInstallationIsExportedWithoutCredentials() {
    val directory = File(context.cacheDir, "migration-export").apply { deleteRecursively() }
    val webStorage = mapOf(
      "ereaderSettings" to """{"theme":"dark","fontScale":1.2}""",
      "ebookLocations-book-1" to "[\"epubcfi(/6/2)\"]",
      "absDeviceId" to "SYNTHETIC-WEB-DEVICE",
      "unrelated" to "dropped",
    )
    val result = LegacyMigrationExporter(context).export(webStorage, directory)

    assertTrue("Only the finished archive is left", directory.listFiles()!!.map { it.name } == listOf(result.file.name))
    assertTrue(result.file.name.endsWith(".absmigration"))
    val raw = result.file.readBytes()
    ZipFile(result.file).use { zip ->
      val entries = zip.entries().toList()
      assertEquals("The manifest is written last, so an interrupted archive has none", "archive.json", entries.last().name)
      val contents = entries.associate { it.name to zip.getInputStream(it).readBytes() }
      contents.forEach { (name, bytes) -> assertFalse("$name carries a secret", String(bytes, Charsets.ISO_8859_1).contains("SYNTHETIC-")) }
      assertFalse(String(raw, Charsets.ISO_8859_1).contains("SYNTHETIC-"))

      val archive: JsonNode = jacksonObjectMapper().readTree(contents.getValue("archive.json"))
      assertEquals(1, archive["formatVersion"].asInt())
      assertEquals("android", archive["platform"].asText())
      val snapshot = archive["snapshot"]
      val connections = snapshot["device"]["serverConnectionConfigs"]
      assertEquals(2, connections.size())
      assertEquals(qa, connections[0]["userId"].asText())
      assertEquals(30, snapshot["device"]["deviceSettings"]["jumpForwardTime"].asInt())
      assertEquals(setOf("userSettings", "bookshelfListView", "theme", "lastLibraryId"), snapshot["preferences"].fieldNames().asSequence().toSet())
      assertEquals(setOf("ereaderSettings", "ebookLocations-book-1"), snapshot["webStorage"].fieldNames().asSequence().toSet())
      assertEquals(4, snapshot["localLibraryItems"].size())
      assertEquals("2", snapshot["localMediaProgress"].first { it["id"].asText() == "local_book-0" }["ebookLocation"].asText())
      assertEquals(7, snapshot["playbackSessions"].single()["timeListening"].asInt())
      assertEquals(1, snapshot["downloadItems"].size())
      assertNotNull("Local history is exported, not only pending server sessions", snapshot["mediaItemHistory"])
      assertEquals("Seek", snapshot["mediaItemHistory"].single()["events"].single()["name"].asText())

      val digests = archive["digests"]
      val stored = archive["storedPaths"]
      // Five present item files, plus the finished part of the running download.
      assertEquals(6, digests.size())
      digests.fields().forEach { (legacyPath, digest) ->
        val bytes = contents[stored[legacyPath].asText()]
        assertNotNull("$legacyPath is in the archive", bytes)
        assertEquals(sha(File(legacyPath).readBytes()), digest.asText())
        assertEquals(digest.asText(), sha(bytes!!))
      }
      assertEquals(listOf(File(downloads, "book-3/track-1.wav").absolutePath), archive["missing"].map { it.asText() })
      assertEquals(result.files, digests.size())
    }

    // The legacy installation is unchanged.
    assertEquals(4, db.getLocalLibraryItems().size)
    assertEquals(1, db.getPlaybackSessions().size)
    assertTrue(File(downloads, "book-0/track-1.wav").exists())

    // Kept for the native app's journey; see android-native/scripts/export-legacy-fixture.sh.
    result.file.copyTo(File(context.getExternalFilesDir(null), "legacy-export.absmigration"), overwrite = true)
  }
}
