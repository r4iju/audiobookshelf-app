package com.audiobookshelf.app.migration

import android.content.Context
import android.net.Uri
import com.audiobookshelf.app.BuildConfig
import com.audiobookshelf.app.managers.DbManager
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.ArrayNode
import com.fasterxml.jackson.databind.node.ObjectNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Writes this installation as one archive for the native app, in the format the iOS export uses
 * (`archive.json` with `formatVersion` 1, files under `files/<digest>/<name>`), zipped because an
 * Android document cannot be a directory. Paper records are kept as this app's own JSON so nothing
 * is reinterpreted on the way out. Credentials never enter the archive: connection tokens and custom
 * headers, refresh tokens, the device record and its Android ID stay here, and the new app signs in
 * again. Nothing in this installation is changed.
 */
class LegacyMigrationExporter(private val context: Context, private val db: DbManager = DbManager()) {
  data class Progress(val phase: String, val completedFiles: Int = 0, val totalFiles: Int = 0, val completedBytes: Long = 0, val totalBytes: Long = 0)
  data class Result(val file: File, val name: String, val files: Int, val bytes: Long)
  class InsufficientSpace(needed: Long, available: Long) : IOException("The export needs ${needed / 1_048_576} MB but only ${available / 1_048_576} MB are free.")

  private class Source(val legacyPath: String, val name: String, val open: () -> InputStream?, val size: Long)

  private val mapper = jacksonObjectMapper()

  fun export(webStorage: Map<String, String>, directory: File, now: Date = Date(), progress: (Progress) -> Unit = {}): Result {
    DbManager.initialize(context)
    progress(Progress("readingDatabase"))
    val snapshot = snapshot(webStorage)
    val sources = sources()
    val present = sources.filter { source -> runCatching { source.open()?.use { true } ?: false }.getOrDefault(false) }
    val missing = sources - present.toSet()
    val totalBytes = present.sumOf { it.size }

    directory.mkdirs()
    val margin = 16L * 1_048_576
    if (directory.usableSpace < totalBytes + margin) throw InsufficientSpace(totalBytes + margin, directory.usableSpace)
    val name = "Audiobookshelf Export ${SimpleDateFormat("yyyy-MM-dd HHmm", Locale.US).format(now)}.absmigration"
    val partial = File(directory, "$name.partial")
    val finished = File(directory, name)
    val digests = mapper.createObjectNode()
    val storedPaths = mapper.createObjectNode()
    try {
      ZipOutputStream(partial.outputStream().buffered()).use { zip ->
        // Audio is already compressed; storing it keeps the export as fast as a copy.
        zip.setLevel(Deflater.NO_COMPRESSION)
        var completedBytes = 0L
        present.forEachIndexed { index, source ->
          progress(Progress("copyingFiles", index, present.size, completedBytes, totalBytes))
          val stored = "files/${hex(sha256(source.legacyPath.toByteArray())).take(24)}/${source.name}"
          val digest = MessageDigest.getInstance("SHA-256")
          zip.putNextEntry(ZipEntry(stored))
          (source.open() ?: throw IOException("${source.name} could not be read")).use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
              val read = input.read(buffer)
              if (read < 0) break
              digest.update(buffer, 0, read)
              zip.write(buffer, 0, read)
              completedBytes += read
            }
          }
          zip.closeEntry()
          digests.put(source.legacyPath, hex(digest.digest()))
          storedPaths.put(source.legacyPath, stored)
        }
        progress(Progress("copyingFiles", present.size, present.size, completedBytes, totalBytes))
        val archive = mapper.createObjectNode().apply {
          put("formatVersion", 1)
          put("platform", "android")
          put("appVersion", BuildConfig.VERSION_NAME)
          put("createdAt", now.time)
          set<JsonNode>("snapshot", snapshot)
          set<JsonNode>("digests", digests)
          set<JsonNode>("storedPaths", storedPaths)
          putArray("missing").apply { missing.forEach { add(it.legacyPath) } }
        }
        // Written last: an archive without its manifest is recognisably incomplete.
        zip.putNextEntry(ZipEntry("archive.json"))
        zip.write(mapper.writeValueAsBytes(archive))
        zip.closeEntry()
      }
      finished.delete()
      if (!partial.renameTo(finished)) throw IOException("The export could not be finished")
    } catch (failure: Throwable) {
      partial.delete()
      throw failure
    }
    return Result(finished, name, present.size, finished.length())
  }

  private fun snapshot(webStorage: Map<String, String>): ObjectNode {
    val device = db.getDeviceData()
    val preferences = context.getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE).all
      .filterKeys { it in PREFERENCE_KEYS }.mapValues { it.value.toString() }
    return mapper.createObjectNode().apply {
      set<JsonNode>("device", mapper.createObjectNode().apply {
        set<JsonNode>("serverConnectionConfigs", mapper.valueToTree<ArrayNode>(device.serverConnectionConfigs))
        put("lastServerConnectionConfigId", device.lastServerConnectionConfigId)
        set<JsonNode>("deviceSettings", mapper.valueToTree(device.deviceSettings))
      })
      set<JsonNode>("preferences", mapper.valueToTree(preferences))
      set<JsonNode>("webStorage", mapper.valueToTree(webStorage.filterKeys { it == "ereaderSettings" || it.startsWith("ebookLocations-") }))
      set<JsonNode>("localFolders", mapper.valueToTree(db.getAllLocalFolders()))
      set<JsonNode>("localLibraryItems", mapper.valueToTree(db.getLocalLibraryItems()))
      set<JsonNode>("localMediaProgress", mapper.valueToTree(db.getAllLocalMediaProgress()))
      set<JsonNode>("playbackSessions", mapper.valueToTree(db.getPlaybackSessions()))
      set<JsonNode>("mediaItemHistory", mapper.valueToTree(db.getAllMediaItemHistory()))
      set<JsonNode>("downloadItems", mapper.valueToTree(db.getDownloadItems()))
    }.also(::scrub)
  }

  /** Removes credentials and the legacy device's identity wherever they appear. */
  private fun scrub(node: JsonNode) {
    when (node) {
      is ObjectNode -> {
        node.remove(SECRET_KEYS)
        node.elements().forEach(::scrub)
      }
      is ArrayNode -> node.forEach(::scrub)
      else -> Unit
    }
  }

  /** Downloaded files of every item, and parts already finished by downloads that were still running. */
  private fun sources(): List<Source> {
    val items = db.getLocalLibraryItems()
    val files = items.flatMap { item ->
      item.localFiles.map { file -> source(file.absolutePath, file.contentUrl, file.filename ?: File(file.absolutePath).name, file.size) } +
        listOfNotNull(item.coverAbsolutePath?.let { path -> source(path, item.coverContentUrl, File(path).name, File(path).length()) })
    }
    val parts = db.getDownloadItems().flatMap { download ->
      download.downloadItemParts.filter { it.completed && it.moved }.map { part -> source(part.finalDestinationPath, null, part.filename, part.fileSize) }
    }
    return (files + parts).distinctBy { it.legacyPath }
  }

  private fun source(path: String, contentUrl: String?, name: String, size: Long): Source {
    val file = File(path)
    val uri = contentUrl?.takeIf { it.startsWith("content:") }?.let(Uri::parse)
    return Source(uri?.toString() ?: path, name.replace('/', '_'), {
      if (uri != null) context.contentResolver.openInputStream(uri) else file.takeIf { it.isFile }?.inputStream()
    }, size)
  }

  private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
  private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

  companion object {
    /** Capacitor Preferences the new app uses; the server settings cache is fetched again at sign-in. */
    val PREFERENCE_KEYS = setOf("userSettings", "playerSettings", "bookshelfListView", "lastLibraryId", "theme", "lang")
    private val SECRET_KEYS = listOf("token", "accessToken", "refreshToken", "customHeaders", "deviceInfo")
  }
}
