package com.audiobookshelf.core.migration

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.LibraryItem
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Import of an archive written by the legacy Android app's own exporter
 * (`LegacyMigrationExportTest` on the emulator; see `scripts/export-legacy-fixture.sh`).
 */
class LegacyImportTest {
    @get:Rule val folder = TemporaryFolder()
    private val qa = AccountIdentity("http://127.0.0.1:28765/abs", "00000000-0000-4000-8000-000000000001")
    private val elsewhere = AccountIdentity("https://elsewhere.invalid", "user-elsewhere")

    private var copies = 0

    private fun exported(): File = folder.root.resolve("legacy-${copies++}.absmigration").also { target ->
        javaClass.getResourceAsStream("/migration/legacy-export.absmigration")!!.use { input -> target.outputStream().use { input.copyTo(it) } }
    }

    /** A copy of the exported archive with [change] applied to its entries. */
    private fun altered(name: String, change: (String, ByteArray) -> ByteArray?): File {
        val target = folder.root.resolve(name)
        ZipFile(exported()).use { zip ->
            ZipOutputStream(target.outputStream()).use { out ->
                zip.entries().toList().forEach { entry ->
                    val bytes = change(entry.name, zip.getInputStream(entry).readBytes()) ?: return@forEach
                    out.putNextEntry(ZipEntry(entry.name)); out.write(bytes); out.closeEntry()
                }
            }
        }
        return target
    }

    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    private val root get() = folder.root.resolve("migration")

    private fun importer() = LegacyImport(root)

    @Test
    fun committedImportPreservesHistoryAndUnknownSnapshotFieldsAcrossRepeatAndSave() {
        val archive = altered("history.absmigration") { name, bytes ->
            if (name == "archive.json") String(bytes).replace("\"snapshot\":{", "\"snapshot\":{\"mediaItemHistory\":[{\"id\":\"local_book-0\",\"events\":[{\"name\":\"Seek\",\"currentTime\":9.5}]}],\"futureReader\":{\"position\":\"opaque\"},").toByteArray() else bytes
        }
        val before = archive.readBytes()
        importer().run(LegacyArchive.open(archive))
        val sourceSnapshot = ZipFile(archive).use { zip ->
            AbsJson.parseToJsonElement(zip.getInputStream(zip.getEntry("archive.json")).reader().readText()).jsonObject.getValue("snapshot")
        }
        val persisted = AbsJson.parseToJsonElement(root.resolve("outcome.json").readText()).jsonObject
        assertEquals("Every exported field survives the public archive/import boundary", sourceSnapshot, persisted["legacySnapshot"])
        val oldOutcome = JsonObject(persisted.filterKeys { it != "legacySnapshot" })
        assertNull("Older committed imports remain readable", AbsJson.decodeFromJsonElement(Outcome.serializer(), oldOutcome).legacySnapshot)
        val committed = importer().outcome()!!
        importer().save(committed.copy(settingsApplied = true))
        assertEquals(committed.copy(settingsApplied = true), importer().run(LegacyArchive.open(archive)))
        assertTrue(root.resolve("outcome.json").readText().contains("opaque"))
        assertTrue("The source archive is unchanged", before.contentEquals(archive.readBytes()))
    }

    @Test
    fun preflightDescribesTheArchiveAndWritesNothing() {
        val archive = LegacyArchive.open(exported())
        val plan = importer().preflight(archive, signedIn = setOf(qa), availableBytes = 10_000_000)

        assertFalse("Preflight writes nothing", root.exists())
        assertEquals(listOf(qa to true, elsewhere to false), plan.accounts.map { it.identity to it.signedIn })
        assertEquals(setOf("book-0", "book-1", "book-4"), plan.titles.map { it.itemId }.toSet())
        assertTrue("The running download keeps only its finished part", plan.titles.single { it.itemId == "book-4" }.partial)
        assertEquals(128044L + 192044 + 8592 + 20 + 128044, plan.requiredBytes)
        assertEquals(setOf(Issue.Kind.ACCOUNT_MISMATCH to "Stories for Tomorrow 03", Issue.Kind.FILE_MISSING to "Stories for Tomorrow 04"), plan.issues.map { it.kind to it.title }.toSet())
        assertTrue(plan.settings)
        assertTrue(plan.fits)
        assertFalse(importer().preflight(archive, signedIn = emptySet(), availableBytes = 400_000).fits)
    }

    @Test
    fun importStagesVerifiedFilesAndCommitsWhatAttachesAfterSignIn() {
        val outcome = importer().run(LegacyArchive.open(exported()))
        assertEquals(3, outcome.titles.size)
        val book = outcome.titles.single { it.itemId == "book-0" }
        assertEquals(qa, book.account)
        assertEquals(listOf("track-1.wav", "track-2.wav"), book.audio.map { it.name })
        assertEquals("pdf", book.ebook?.ebookFormat)
        book.files.forEach { file -> assertEquals(file.digest, sha(importer().staged(file))) }
        assertEquals("epub", outcome.titles.single { it.itemId == "book-1" }.ebook?.ebookFormat)
        assertEquals(listOf("legacy-session-1"), outcome.sessions.map { it.session.id })
        assertEquals(7.0, outcome.sessions.single().session.timeListening, 0.0)
        assertEquals(setOf("2", "epubcfi(/6/4!/4/2/1:0)"), outcome.progress.mapNotNull { it.progress.ebookLocation }.toSet())
        assertEquals(setOf("ereaderSettings", "ebookLocations-book-1"), outcome.webStorage.keys)
        assertEquals(qa to "qa", outcome.accounts.first().let { it.identity to it.username })
        assertTrue("Nothing is attached before sign-in", outcome.titles.none { it.attached })
        assertEquals(outcome, importer().outcome())
    }

    @Test
    fun aCorruptFileIsReportedAndItsTitleIsNotAdoptedWhileTheRestImports() {
        val archive = altered("corrupt.absmigration") { name, bytes -> if (name.endsWith("stories.pdf")) bytes.copyOf().also { it[100] = (it[100] + 1).toByte() } else bytes }
        val outcome = importer().run(LegacyArchive.open(archive))
        assertEquals(setOf("book-1", "book-4"), outcome.titles.map { it.itemId }.toSet())
        assertTrue(outcome.issues.any { it.kind == Issue.Kind.FILE_CORRUPT && it.title == "Stories for Tomorrow 01" })
        assertTrue("The archive itself is kept", archive.exists())
    }

    @Test
    fun anInterruptedImportResumesWithoutCopyingVerifiedFilesAgain() {
        val archive = LegacyArchive.open(exported())
        var copied = 0
        try {
            importer().run(archive) { if (++copied == 2) throw InterruptedException("process ended") }
            fail("The import was interrupted")
        } catch (expected: InterruptedException) {}
        assertNull("Nothing is committed by an interrupted import", importer().outcome())

        val again = mutableListOf<String>()
        val outcome = importer().run(LegacyArchive.open(exported())) { again += it }
        assertEquals("Only files not yet verified are copied again", 3, again.size)
        assertEquals(3, outcome.titles.size)
    }

    @Test
    fun theSameArchiveIsNotImportedTwiceAndAnotherIsRefusedAfterCommit() {
        val first = importer().run(LegacyArchive.open(exported()))
        val copies = mutableListOf<String>()
        assertEquals(first, importer().run(LegacyArchive.open(exported())) { copies += it })
        assertTrue(copies.isEmpty())

        val other = altered("other.absmigration") { name, bytes -> if (name == "archive.json") String(bytes).replace("\"createdAt\":", "\"createdAt\":1,\"x\":").toByteArray() else bytes }
        try {
            importer().run(LegacyArchive.open(other))
            fail("A second archive was imported over the first")
        } catch (expected: MigrationError.AnotherArchiveImported) {}
        assertEquals(first, importer().outcome())
    }

    @Test
    fun archivesThisAppCannotImportAreRefused() {
        val refusals = mapOf(
            altered("incomplete.absmigration") { name, bytes -> bytes.takeIf { name != "archive.json" } } to MigrationError.Incomplete::class,
            altered("future.absmigration") { name, bytes -> if (name == "archive.json") String(bytes).replace("\"formatVersion\":1", "\"formatVersion\":2").toByteArray() else bytes } to MigrationError.Unsupported::class,
            altered("iphone.absmigration") { name, bytes -> if (name == "archive.json") String(bytes).replace("\"platform\":\"android\"", "\"platform\":\"ios\"").toByteArray() else bytes } to MigrationError.FromAnotherPlatform::class,
            folder.newFile("garbage.absmigration").apply { writeText("not a zip") } to MigrationError.Unreadable::class,
        )
        refusals.forEach { (file, expected) ->
            try {
                LegacyArchive.open(file)
                fail("${file.name} was accepted")
            } catch (refused: MigrationError) {
                assertEquals(file.name, expected, refused::class)
            }
        }
    }

    @Test
    fun stagedFilesAreMatchedToTheServerItemsTracksAndEbook() {
        val title = importer().run(LegacyArchive.open(exported())).titles.single { it.itemId == "book-0" }
        val item = AbsJson.decodeFromString(LibraryItem.serializer(), """{"id":"book-0","mediaType":"book","media":{"duration":20,
            "tracks":[{"index":1,"duration":8,"contentUrl":"/api/items/book-0/file/0","mimeType":"audio/wav"},{"index":2,"startOffset":8,"duration":12,"contentUrl":"/api/items/book-0/file/1","mimeType":"audio/wav"}],
            "ebookFile":{"ino":"pdf","ebookFormat":"pdf"}}}""")
        val match = Attachment.match(title, item, episodeId = null)
        assertNull(match.problem)
        assertEquals(listOf("track-1.wav", "track-2.wav"), match.audio.map { it?.name })
        assertEquals("stories.pdf", match.ebook?.name)

        val changed = item.copy(media = item.media.copy(tracks = item.media.tracks.take(1)))
        assertTrue("A title whose tracks changed on the server is not attached", Attachment.match(title, changed, null).problem != null)
    }

    @Test
    fun aRunningDownloadKeepsItsFinishedPartInItsPlaceAndFetchesTheRest() {
        val title = importer().run(LegacyArchive.open(exported())).titles.single { it.itemId == "book-4" }
        // Server items list tracks in order; the index may be absent, as on the fixture.
        val item = AbsJson.decodeFromString(LibraryItem.serializer(), """{"id":"book-4","mediaType":"book","media":{"duration":20,
            "tracks":[{"duration":8,"contentUrl":"/api/items/book-4/file/0","mimeType":"audio/wav"},{"startOffset":8,"duration":12,"contentUrl":"/api/items/book-4/file/1","mimeType":"audio/wav"}]}}""")
        val match = Attachment.match(title, item, episodeId = null)
        assertNull(match.problem)
        assertEquals(listOf("track-1.wav", null), match.audio.map { it?.name })
    }

    @Test
    fun anArchiveWhoseDigestsOrPathsCouldLeaveStagingIsRefusedBeforeAnythingIsWritten() {
        val sentinel = folder.root.resolve("planted.tmp").apply { writeText("kept") }
        val escaping = altered("escaping.absmigration") { name, bytes ->
            if (name != "archive.json") bytes
            else Regex("\"digests\":\\{\"([^\"]+)\":\"[0-9a-f]{64}\"").replace(String(bytes)) { "\"digests\":{\"${it.groupValues[1]}\":\"../../planted\"" }.toByteArray()
        }
        val outside = altered("outside.absmigration") { name, bytes ->
            if (name != "archive.json") bytes else Regex("\"storedPaths\":\\{\"([^\"]+)\":\"[^\"]+\"").replace(String(bytes)) { "\"storedPaths\":{\"${it.groupValues[1]}\":\"../archive.json\"" }.toByteArray()
        }
        for (file in listOf(escaping, outside)) {
            try {
                importer().run(LegacyArchive.open(file))
                fail("${file.name} was imported")
            } catch (expected: MigrationError.Unreadable) {}
        }
        assertEquals("kept", sentinel.readText())
        assertFalse(root.resolve("staging").exists())
    }

    @Test
    fun aFileThatCannotBeMovedIntoPlaceInterruptsTheImportInsteadOfCountingAsCorrupt() {
        try {
            importer().run(LegacyArchive.open(exported())) { throw InterruptedException("process ended") }
            fail("The import was interrupted")
        } catch (expected: InterruptedException) {}
        val staging = root.resolve("staging")
        val waiting = LegacyArchive.open(exported()).manifest.digests.values.filterNot { staging.resolve(it).exists() }
        // A directory in a file's place makes moving it there fail, as a full or failing disk would.
        waiting.forEach { staging.resolve(it).resolve("blocker").mkdirs() }
        try {
            importer().run(LegacyArchive.open(exported()))
            fail("The import went ahead without its files")
        } catch (expected: java.io.IOException) {}
        assertNull("Nothing is committed while files cannot be placed", importer().outcome())

        waiting.forEach { staging.resolve(it).deleteRecursively() }
        val outcome = importer().run(LegacyArchive.open(exported()))
        assertEquals(3, outcome.titles.size)
        assertTrue(outcome.issues.none { it.kind == Issue.Kind.FILE_CORRUPT })
    }

    @Test
    fun aPdfDownloadedWithoutItsTitlesAudioIsMatchedOnItsOwn() {
        val pdf = importer().run(LegacyArchive.open(exported())).titles.single { it.itemId == "book-0" }.ebook!!
        val companion = ImportedTitle(qa, "book-0", null, "Stories for Tomorrow 01", "", "book", listOf(pdf))
        val item = AbsJson.decodeFromString(LibraryItem.serializer(), """{"id":"book-0","mediaType":"book","media":{"duration":20,
            "tracks":[{"index":1,"duration":8,"contentUrl":"/api/items/book-0/file/0","mimeType":"audio/wav"},{"index":2,"startOffset":8,"duration":12,"contentUrl":"/api/items/book-0/file/1","mimeType":"audio/wav"}],
            "ebookFile":{"ino":"pdf","ebookFormat":"pdf"}}}""")
        val match = Attachment.match(companion, item, episodeId = null)
        assertNull(match.problem)
        assertTrue(match.audio.isEmpty())
        assertEquals("stories.pdf", match.ebook?.name)
    }

    @Test
    fun listeningWithImpossibleValuesIsReportedAndLeftOutSoTheRestAttaches() {
        val archive = altered("negative.absmigration") { name, bytes ->
            if (name == "archive.json") String(bytes).replace("\"timeListening\":7", "\"timeListening\":-7").toByteArray() else bytes
        }
        val outcome = importer().run(LegacyArchive.open(archive))
        assertTrue(outcome.sessions.isEmpty())
        assertTrue(outcome.issues.any { it.kind == Issue.Kind.INVALID_RECORD && it.title == "Stories for Tomorrow 01" })
        assertEquals(3, outcome.titles.size)
    }

    @Test
    fun aStagedFileDamagedWhileTheImportWasInterruptedIsCopiedAgainFromTheArchive() {
        try {
            importer().run(LegacyArchive.open(exported())) { throw InterruptedException("process ended") }
            fail("The import was interrupted")
        } catch (expected: InterruptedException) {}
        val damaged = root.resolve("staging").listFiles()!!.single { it.name.length == 64 }
        damaged.writeBytes(damaged.readBytes().copyOf(10))

        val again = mutableListOf<String>()
        val outcome = importer().run(LegacyArchive.open(exported())) { again += it }
        assertEquals(damaged.name, sha(damaged))
        assertEquals("The damaged file and the rest are copied", 5, again.size)
        assertEquals(3, outcome.titles.size)
    }

    @Test
    fun aStagedFileDamagedAfterTheImportIsNotOfferedForAdoption() {
        val title = importer().run(LegacyArchive.open(exported())).titles.single { it.itemId == "book-0" }
        val pdf = title.ebook!!
        assertEquals(importer().staged(pdf), importer().verified(pdf))
        importer().staged(pdf).appendBytes(byteArrayOf(1))
        assertNull(importer().verified(pdf))
    }
}
