package com.audiobookshelf.app.plugins

import android.app.Activity
import android.content.Intent
import androidx.activity.result.ActivityResult
import com.audiobookshelf.app.migration.LegacyMigrationExporter
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.File

/** Exports this installation for the native app; see [LegacyMigrationExporter]. Same JS API as the iOS plugin. */
@CapacitorPlugin(name = "LegacyMigrationExport")
class LegacyMigrationExportPlugin : Plugin() {
  @Volatile private var busy = false
  @Volatile private var archive: File? = null
  private val directory get() = File(context.cacheDir, "migration-export")

  @PluginMethod
  fun exportArchive(call: PluginCall) {
    if (busy) return call.reject("An export is already running.", "EXPORT_BUSY")
    busy = true
    val storage = call.getObject("webStorage") ?: JSObject()
    val webStorage = storage.keys().asSequence().associateWith { storage.optString(it) }
    Thread {
      try {
        directory.deleteRecursively()
        val result = LegacyMigrationExporter(context).export(webStorage, directory) { progress ->
          notifyListeners("exportProgress", JSObject().apply {
            put("phase", progress.phase)
            put("completedFiles", progress.completedFiles)
            put("totalFiles", progress.totalFiles)
            put("completedBytes", progress.completedBytes)
            put("totalBytes", progress.totalBytes)
          })
        }
        archive = result.file
        call.resolve(JSObject().apply { put("name", result.name); put("files", result.files); put("bytes", result.bytes) })
      } catch (failure: Exception) {
        AbsLogger.error("LegacyMigrationExport", "Export failed: ${failure.javaClass.simpleName}")
        call.reject(failure.message ?: "The export failed. Nothing was changed.", "EXPORT_FAILED", failure)
      } finally {
        busy = false
      }
    }.start()
  }

  @PluginMethod
  fun saveArchive(call: PluginCall) {
    val file = archive?.takeIf { it.exists() } ?: return call.reject("Export again first.", "SAVE_FAILED")
    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
      .setType("application/octet-stream").putExtra(Intent.EXTRA_TITLE, file.name)
    startActivityForResult(call, intent, "archiveSaved")
  }

  @ActivityCallback
  private fun archiveSaved(call: PluginCall, result: ActivityResult) {
    val file = archive
    val uri = result.data?.data
    if (result.resultCode != Activity.RESULT_OK || uri == null || file == null) return call.resolve(JSObject().put("saved", false))
    Thread {
      try {
        (context.contentResolver.openOutputStream(uri, "wt") ?: throw java.io.IOException("The chosen file could not be written")).use { output ->
          file.inputStream().use { it.copyTo(output, 1 shl 16) }
        }
        call.resolve(JSObject().put("saved", true))
      } catch (failure: Exception) {
        call.reject(failure.message ?: "The file could not be saved.", "SAVE_FAILED", failure)
      }
    }.start()
  }

  @PluginMethod
  fun discardArchive(call: PluginCall) {
    if (busy) return call.reject("An export is still running.", "DISCARD_FAILED")
    directory.deleteRecursively()
    archive = null
    call.resolve()
  }
}
