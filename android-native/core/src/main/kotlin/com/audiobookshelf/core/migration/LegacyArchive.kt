package com.audiobookshelf.core.migration

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import com.audiobookshelf.core.AbsJson
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipFile

/** The legacy app's records, as its own JSON (see the legacy `LegacyMigrationExporter`). */
@Serializable data class LegacyConnection(val id: String, val index: Int = 0, val name: String = "", val address: String, val version: String? = null, val userId: String, val username: String = "")

@Serializable data class LegacyDevice(
    val serverConnectionConfigs: List<LegacyConnection> = emptyList(),
    val lastServerConnectionConfigId: String? = null,
    val deviceSettings: JsonObject? = null,
)

@Serializable data class LegacyFile(val id: String, val filename: String? = null, val contentUrl: String = "", val absolutePath: String = "", val mimeType: String? = null, val size: Long = 0)

@Serializable data class LegacyTrack(val index: Int = 0, val startOffset: Double = 0.0, val duration: Double = 0.0, val title: String? = null, val mimeType: String? = null, val localFileId: String? = null, val serverIndex: Int? = null)

@Serializable data class LegacyEbook(val ino: String, val ebookFormat: String, val localFileId: String? = null)

@Serializable data class LegacyEpisode(val id: String, val title: String? = null, val audioTrack: LegacyTrack? = null, val duration: Double? = null, val serverEpisodeId: String? = null)

@Serializable data class LegacyMetadata(val title: String = "", val authorName: String? = null, val author: String? = null)

@Serializable data class LegacyMedia(
    val metadata: LegacyMetadata = LegacyMetadata(),
    val tracks: List<LegacyTrack>? = null,
    val chapters: List<LegacyChapter>? = null,
    val ebookFile: LegacyEbook? = null,
    val episodes: List<LegacyEpisode>? = null,
    val duration: Double? = null,
)

@Serializable data class LegacyChapter(val id: Int = 0, val start: Double, val end: Double, val title: String? = null)

@Serializable data class LegacyItem(
    val id: String,
    val libraryItemId: String? = null,
    val mediaType: String = "book",
    val media: LegacyMedia = LegacyMedia(),
    val localFiles: List<LegacyFile> = emptyList(),
    val isInvalid: Boolean = false,
    val coverAbsolutePath: String? = null,
    val serverConnectionConfigId: String? = null,
    val serverAddress: String? = null,
    val serverUserId: String? = null,
)

@Serializable data class LegacyProgress(
    val id: String,
    val localLibraryItemId: String,
    val localEpisodeId: String? = null,
    val duration: Double = 0.0,
    val progress: Double = 0.0,
    val currentTime: Double = 0.0,
    val isFinished: Boolean = false,
    val ebookLocation: String? = null,
    val ebookProgress: Double? = null,
    val lastUpdate: Long = 0,
    val startedAt: Long = 0,
    val finishedAt: Long? = null,
    val serverConnectionConfigId: String? = null,
    val serverAddress: String? = null,
    val serverUserId: String? = null,
    val libraryItemId: String? = null,
    val episodeId: String? = null,
)

@Serializable data class LegacySession(
    val id: String,
    val userId: String? = null,
    val libraryItemId: String? = null,
    val episodeId: String? = null,
    val mediaType: String = "book",
    val displayTitle: String? = null,
    val displayAuthor: String? = null,
    val duration: Double = 0.0,
    val playMethod: Int = 3,
    val startTime: Double = 0.0,
    val startedAt: Long = 0,
    val updatedAt: Long = 0,
    val timeListening: Double = 0.0,
    val currentTime: Double = 0.0,
    val serverConnectionConfigId: String? = null,
    val serverAddress: String? = null,
)

@Serializable data class LegacyPart(
    val id: String,
    val filename: String = "",
    val fileSize: Long = 0,
    val finalDestinationPath: String = "",
    val completed: Boolean = false,
    val moved: Boolean = false,
    val failed: Boolean = false,
    val ebookFile: LegacyEbook? = null,
    val audioTrack: LegacyTrack? = null,
    val episode: LegacyEpisode? = null,
)

@Serializable data class LegacyDownload(
    val id: String,
    val libraryItemId: String,
    val episodeId: String? = null,
    val serverConnectionConfigId: String = "",
    val serverAddress: String = "",
    val serverUserId: String = "",
    val mediaType: String = "book",
    val itemTitle: String = "",
    val downloadItemParts: List<LegacyPart> = emptyList(),
)

@Serializable data class LegacySnapshot(
    val device: LegacyDevice = LegacyDevice(),
    val preferences: Map<String, String> = emptyMap(),
    val webStorage: Map<String, String> = emptyMap(),
    val localLibraryItems: List<LegacyItem> = emptyList(),
    val localMediaProgress: List<LegacyProgress> = emptyList(),
    val playbackSessions: List<LegacySession> = emptyList(),
    val downloadItems: List<LegacyDownload> = emptyList(),
)

@Serializable data class LegacyManifest(
    val formatVersion: Int,
    val platform: String? = null,
    val appVersion: String? = null,
    val createdAt: Long? = null,
    val snapshot: LegacySnapshot = LegacySnapshot(),
    val digests: Map<String, String> = emptyMap(),
    val storedPaths: Map<String, String> = emptyMap(),
    val missing: List<String> = emptyList(),
)

sealed class MigrationError(message: String) : java.io.IOException(message) {
    class Unreadable : MigrationError("This file is not an export from the previous app, or it is damaged.")
    class Incomplete : MigrationError("This export was not finished. Export again in the previous app.")
    class Unsupported(version: Int) : MigrationError("This export (format $version) is from a newer app. Update this app first.")
    class FromAnotherPlatform(platform: String?) : MigrationError("This export was made by the ${if (platform == "ios") "iPhone" else platform ?: "other"} app. Export again from the Android app.")
    class AnotherArchiveImported : MigrationError("Another export was already imported on this device.")
    class InsufficientSpace(val needed: Long, val available: Long) : MigrationError("The import needs ${needed / 1_048_576 + 1} MB but only ${available / 1_048_576} MB are free.")
}

/** An export archive from the legacy Android app (format 1, zipped). */
class LegacyArchive private constructor(val file: File, val manifest: LegacyManifest, val fingerprint: String, val snapshotDocument: JsonObject) {
    fun <T> read(stored: String, block: (InputStream) -> T): T = ZipFile(file).use { zip ->
        val entry = zip.getEntry(stored) ?: throw MigrationError.Unreadable()
        zip.getInputStream(entry).use(block)
    }

    companion object {
        private val DIGEST = Regex("[0-9a-f]{64}")
        private val STORED = Regex("files/[0-9a-f]{24}/[^/]+")

        fun open(file: File): LegacyArchive {
            val entries: Set<String>
            val bytes = try {
                ZipFile(file).use { zip ->
                    entries = zip.entries().asSequence().map { it.name }.toSet()
                    zip.getEntry("archive.json")?.let { entry -> zip.getInputStream(entry).use { it.readBytes() } }
                }
            } catch (failure: IOException) {
                throw MigrationError.Unreadable()
            } ?: throw MigrationError.Incomplete()
            val document = try { AbsJson.parseToJsonElement(String(bytes)).jsonObject } catch (failure: Exception) { throw MigrationError.Unreadable() }
            val platform = document["platform"]?.jsonPrimitive?.contentOrNull
            if (platform != "android") throw MigrationError.FromAnotherPlatform(platform)
            val version = document["formatVersion"]?.jsonPrimitive?.intOrNull ?: throw MigrationError.Unreadable()
            if (version != 1) throw MigrationError.Unsupported(version)
            val manifest = try { AbsJson.decodeFromJsonElement(LegacyManifest.serializer(), document) } catch (failure: Exception) { throw MigrationError.Unreadable() }
            // Digests name staged files, so anything but a SHA-256 could address a path outside staging.
            if (manifest.digests.values.any { !DIGEST.matches(it) }) throw MigrationError.Unreadable()
            if (manifest.storedPaths.any { (path, stored) -> path !in manifest.digests || !STORED.matches(stored) || ".." in stored.split('/') || stored !in entries }) throw MigrationError.Unreadable()
            val fingerprint = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            return LegacyArchive(file, manifest, fingerprint, document["snapshot"]?.jsonObject ?: JsonObject(emptyMap()))
        }
    }
}
