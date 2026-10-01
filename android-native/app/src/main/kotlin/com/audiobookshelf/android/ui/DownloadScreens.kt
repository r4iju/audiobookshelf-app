package com.audiobookshelf.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.runtime.mutableIntStateOf
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.audiobookshelf.android.data.DeviceSettings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.download.DownloadStore
import com.audiobookshelf.android.download.Downloads
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.Episode
import com.audiobookshelf.core.LibraryItem
import java.io.File

private fun DownloadStore.Record.fraction(): Float? = total?.takeIf { it > 0 }?.let { (bytes.toFloat() / it).coerceIn(0f, 1f) }

private fun formatBytes(bytes: Long): String = when {
    bytes >= 1L shl 30 -> "%.1f GB".format(bytes / (1L shl 30).toDouble())
    bytes >= 1L shl 20 -> "%.0f MB".format(bytes / (1L shl 20).toDouble())
    else -> "%.0f KB".format(bytes / 1024.0)
}

/** Download state and actions for one book or episode on its detail screen. */
@Composable
fun DownloadButton(item: LibraryItem, episode: Episode?, active: SessionState.Active, catalog: CatalogModel) {
    val graph = LocalContext.current.graph
    val all by graph.downloads.records.collectAsState()
    val record = all.firstOrNull { it.id == Downloads.recordId(active.client.account, item.id, episode?.id) }
    var message by remember(item.id, episode?.id) { mutableStateOf<String?>(null) }
    var askCellular by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    val canDownload = catalog.user?.permissions?.download ?: true

    fun start(allowMetered: Boolean) {
        message = when (val result = graph.downloads.request(active.client, item, episode, canDownload, allowMetered)) {
            Downloads.Request.Started -> null
            Downloads.Request.NotAllowed -> "Your account is not allowed to download."
            Downloads.Request.NoAudio -> "This item has no audio to download."
            Downloads.Request.NeedsCellularConsent -> { askCellular = true; null }
            is Downloads.Request.NoSpace -> "Not enough free space on this device for ${formatBytes(result.needed)} while keeping storage free for the system."
            Downloads.Request.NotSaved -> NOT_SAVED
            is Downloads.Request.FolderLost -> "Access to ${result.name} was removed, so nothing was downloaded. Choose the download folder again in Settings."
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when (record?.state) {
            null -> if (canDownload) OutlinedButton(onClick = { start(false) }, modifier = Modifier.fillMaxWidth().testTag("download")) {
                Icon(Icons.Outlined.Download, null); Text("Download", Modifier.padding(start = 6.dp))
            }
            DownloadStore.State.QUEUED, DownloadStore.State.RUNNING -> Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("download-progress")) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val fraction = record.fraction()
                    Text(record.error ?: if (fraction != null) "Downloading ${(fraction * 100).toInt()}%" else "Downloading…", style = MaterialTheme.typography.bodyMedium)
                    if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth()) else LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                IconButton(onClick = { if (!graph.downloads.delete(record.id)) message = NOT_SAVED }, modifier = Modifier.testTag("download-cancel")) { Icon(Icons.Outlined.Close, "Cancel download") }
            }
            DownloadStore.State.COMPLETE -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                Text("Downloaded · plays offline", Modifier.weight(1f).padding(start = 8.dp).testTag("downloaded"))
                TextButton(onClick = { confirmRemove = true }, modifier = Modifier.testTag("download-remove")) { Text("Remove") }
            }
            DownloadStore.State.FAILED -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(record.error ?: "The download failed.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("download-error"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { if (!graph.downloads.retry(record.id)) message = NOT_SAVED }, modifier = Modifier.testTag("download-retry")) { Icon(Icons.Outlined.Refresh, null); Text("Retry", Modifier.padding(start = 6.dp)) }
                    TextButton(onClick = { if (!graph.downloads.delete(record.id)) message = NOT_SAVED }) { Text("Discard") }
                }
            }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("download-message")) }
    }

    if (askCellular) AlertDialog(
        onDismissRequest = { askCellular = false },
        title = { Text("Download on mobile data?") },
        text = { Text("You are on a metered connection. You can change this in Settings.") },
        confirmButton = { TextButton(onClick = { askCellular = false; start(true) }, modifier = Modifier.testTag("download-cellular-allow")) { Text("Download") } },
        dismissButton = { TextButton(onClick = { askCellular = false }) { Text("Not now") } },
    )
    if (confirmRemove && record != null) RemoveDialog(record.title, onDismiss = { confirmRemove = false }) { confirmRemove = false; if (!remove(graph, record)) message = NOT_SAVED }
}

/** Where new downloads go: app storage, or a folder the user chose and can reach from other apps. */
@Composable
fun DownloadLocation(settings: DeviceSettings, change: ((DeviceSettings) -> DeviceSettings) -> Unit) {
    val graph = LocalContext.current.graph
    var problem by remember { mutableStateOf<String?>(null) }
    fun releaseUnused(tree: String?) {
        if (tree != null && graph.downloads.records.value.none { it.folder == tree }) graph.downloads.folder.release(tree)
    }
    val choose = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        if (tree == null) return@rememberLauncherForActivityResult
        problem = try {
            val name = graph.downloads.folder.adopt(tree)
            val previous = settings.downloadFolder
            change { it.copy(downloadFolder = tree.toString(), downloadFolderName = name) }
            if (previous != tree.toString()) releaseUnused(previous)
            null
        } catch (failure: SecurityException) {
            "That folder cannot be kept for downloads. Choose another one."
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(settings.downloadFolder?.let { "Downloads are saved in ${settings.downloadFolderName}" } ?: "Downloads are saved in app storage",
            style = MaterialTheme.typography.bodyLarge, modifier = Modifier.testTag("download-folder"))
        Text(if (settings.downloadFolder != null) "Other apps on this device can see these files. Downloads made before a change stay where they are."
            else "Only this app can see these files. Choose a folder to keep downloads where other apps can reach them.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { choose.launch(null) }, modifier = Modifier.testTag("choose-download-folder")) {
                Icon(Icons.Outlined.Folder, null); Text("Choose folder", Modifier.padding(start = 6.dp))
            }
            if (settings.downloadFolder != null) TextButton(onClick = {
                val previous = settings.downloadFolder
                change { it.copy(downloadFolder = null, downloadFolderName = null) }
                releaseUnused(previous)
            }, modifier = Modifier.testTag("use-app-storage")) { Text("Use app storage") }
        }
        problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
    }
}

private fun ebookType(format: String?) = when (format?.lowercase()) {
    "pdf" -> "application/pdf"
    "epub" -> "application/epub+zip"
    "mobi" -> "application/x-mobipocket-ebook"
    "azw3", "azw" -> "application/vnd.amazon.ebook"
    "cbz" -> "application/vnd.comicbook+zip"
    "cbr" -> "application/vnd.comicbook-rar"
    else -> android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(format?.lowercase()) ?: "application/octet-stream"
}

/**
 * Hands the downloaded ebook to another app with read access to that one file only, for formats this
 * app does not open itself and for readers people prefer. Returns why it did not open, if it did not.
 */
private fun openElsewhere(context: Context, graph: com.audiobookshelf.android.AppGraph, record: DownloadStore.Record): String? {
    val part = record.ebook ?: return null
    val format = part.ebookFormat?.uppercase() ?: "this kind of"
    return when (val opened = graph.downloads.openPart(record, part)) {
        Downloads.Opened.Missing -> "The ebook is missing from this device. Download it again to open it."
        is Downloads.Opened.FolderLost -> folderLostMessage(opened.name, "open")
        is Downloads.Opened.Readable -> try {
            context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(opened.uri, ebookType(part.ebookFormat)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            null
        } catch (missing: ActivityNotFoundException) {
            "No app on this device opens $format files. Install one that does and try again."
        }
    }
}

private fun folderLostMessage(name: String, verb: String) =
    "This download is in $name, and access to $name was removed. Choose $name again to $verb it."

private const val NOT_SAVED = "The download list could not be saved on this device, so nothing changed. Free some storage and try again."

private fun remove(graph: com.audiobookshelf.android.AppGraph, record: DownloadStore.Record): Boolean {
    val now = graph.playback.state.value.now
    if (now != null && now.local && now.itemId == record.itemId && now.episodeId == record.episodeId) graph.playback.close()
    return graph.downloads.delete(record.id)
}

@Composable
private fun RemoveDialog(title: String, onDismiss: () -> Unit, onConfirm: () -> Unit) = AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text("Remove download?") },
    text = { Text("\"$title\" will be removed from this device. Your listening progress is kept.") },
    confirmButton = { TextButton(onClick = onConfirm, modifier = Modifier.testTag("confirm-delete-download")) { Text("Remove") } },
    dismissButton = { TextButton(onClick = onDismiss) { Text("Keep") } },
)

/** Everything downloaded for the active account; works without the server. */
@Composable
fun DownloadsScreen(active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onRead: (Route) -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val all by graph.downloads.records.collectAsState()
    val records = all.filter { it.account == active.client.account }.sortedByDescending { it.createdAt }
    var removing by remember { mutableStateOf<DownloadStore.Record?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    // Grants and files can change outside the app, so they are looked at again whenever it returns.
    var looked by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) { looked++; onPauseOrDispose {} }
    val lost = remember(records, looked) { records.filter(graph.downloads::folderLost) }
    val missing = remember(records, looked) { records.filter(graph.downloads::missing).map { it.id }.toSet() }
    val regain = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        if (tree == null) return@rememberLauncherForActivityResult
        val names = lost.mapNotNull { it.folderName }.distinct().joinToString(" or ")
        message = try {
            if (graph.downloads.regainFolder(tree)) null else "That is not $names. Choose the folder these downloads are in."
        } catch (failure: SecurityException) { "Access to that folder could not be kept. Try again." }
        looked++
    }
    if (records.isEmpty()) {
        MessageState("No downloads", "Download books or episodes from their page to listen without a connection.", Modifier.padding(padding), tag = "downloads-empty")
        return
    }
    // Notices stay above the list: an item inserted above the first visible row would be scrolled out of view.
    Column(Modifier.fillMaxSize().padding(padding)) {
        if (lost.isNotEmpty()) {
            val names = lost.mapNotNull { it.folderName }.distinct().joinToString(" and ")
            Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp).testTag("folder-access-lost"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Access to $names was removed", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                Text("${lost.size} ${if (lost.size == 1) "download is" else "downloads are"} kept there. Choose $names again to play and open ${if (lost.size == 1) "it" else "them"}.", style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = { regain.launch(null) }, modifier = Modifier.testTag("choose-folder-again")) { Text("Choose $names again") }
            }
        }
        message?.let { text -> Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp).testTag("downloads-message")) }
        LazyColumn(Modifier.weight(1f).testTag("downloads"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(records, key = { it.id }) { record ->
                val key = record.key
                val tag = when (record.state) {
                    DownloadStore.State.COMPLETE -> "offline-$key"
                    DownloadStore.State.FAILED -> "download-failed-$key"
                    else -> "downloading-$key"
                }
                Row(Modifier.fillMaxWidth().testTag(tag), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Cover(File(record.directory, "cover.jpg").takeIf { it.exists() }, record.title, Modifier.size(56.dp), podcast = record.mediaType == "podcast")
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                        Text(record.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (record.author.isNotBlank()) Text(record.author, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        when (record.state) {
                            DownloadStore.State.COMPLETE -> if (record.id in missing) Text("Some files are missing from this device", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                else Text(listOfNotNull(formatBytes(record.bytes.takeIf { it > 0 } ?: record.total ?: 0), record.folderName?.let { "in $it" }).joinToString(" "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            DownloadStore.State.FAILED -> Text(record.error ?: "The download failed.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                            else -> {
                                val fraction = record.fraction()
                                if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) else LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 4.dp))
                                record.error?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                            }
                        }
                    }
                    val readable = record.ebook?.takeIf { record.state == DownloadStore.State.COMPLETE && it.ebookFormat == "pdf" }
                    if (readable != null) IconButton(
                        onClick = { onRead(Route.Reader(record.itemId, readable.ebookFileId!!, supplementary = false, title = record.title, downloadId = record.id)) },
                        modifier = Modifier.testTag("read-offline-$key"),
                    ) { Icon(Icons.AutoMirrored.Outlined.MenuBook, "Read ${record.title}") }
                    if (record.state == DownloadStore.State.COMPLETE && record.ebook != null && record.id !in missing) IconButton(
                        onClick = { message = openElsewhere(context, graph, record); looked++ },
                        modifier = Modifier.testTag("open-elsewhere-$key"),
                    ) { Icon(Icons.AutoMirrored.Outlined.OpenInNew, "Open ${record.title} in another app") }
                    when {
                        record.id in missing -> IconButton(onClick = { message = if (graph.downloads.retry(record.id)) null else NOT_SAVED }, modifier = Modifier.testTag("download-retry-$key")) { Icon(Icons.Outlined.Refresh, "Download ${record.title} again") }
                        record.state == DownloadStore.State.COMPLETE -> if (record.audio.isNotEmpty()) IconButton(
                            onClick = {
                                message = when {
                                    graph.downloads.folderLost(record) -> folderLostMessage(record.folderName ?: "the chosen folder", "play")
                                    graph.downloads.missing(record) -> "Some files of this download are missing from this device. Download it again to play it."
                                    else -> { graph.playback.play(graph.downloads.localSource(record, catalog.progressFor(record.itemId, record.episodeId))); null }
                                }
                                looked++
                            },
                            modifier = Modifier.testTag("play-offline-$key"),
                        ) { Icon(Icons.Filled.PlayArrow, "Play ${record.title}") }
                        record.state == DownloadStore.State.FAILED -> IconButton(onClick = { message = if (graph.downloads.retry(record.id)) null else NOT_SAVED }, modifier = Modifier.testTag("download-retry-$key")) { Icon(Icons.Outlined.Refresh, "Retry ${record.title}") }
                        else -> IconButton(onClick = { message = if (graph.downloads.delete(record.id)) null else NOT_SAVED }, modifier = Modifier.testTag("cancel-download-$key")) { Icon(Icons.Outlined.Close, "Cancel ${record.title}") }
                    }
                    if (record.state != DownloadStore.State.QUEUED && record.state != DownloadStore.State.RUNNING) {
                        IconButton(onClick = { removing = record }, modifier = Modifier.testTag("delete-download-$key")) { Icon(Icons.Outlined.Delete, "Remove ${record.title}") }
                    }
                }
            }
        }
    }
    removing?.let { record -> RemoveDialog(record.title, onDismiss = { removing = null }) { removing = null; message = if (remove(graph, record)) null else NOT_SAVED } }
}
