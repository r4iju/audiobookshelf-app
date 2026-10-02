package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.material.icons.outlined.DownloadForOffline
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
import androidx.compose.foundation.layout.FlowRow
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
    val context = LocalContext.current
    val graph = context.graph
    val notSaved = stringResource(R.string.dl_not_saved)
    val all by graph.downloads.records.collectAsState()
    val record = all.firstOrNull { it.id == Downloads.recordId(active.client.account, item.id, episode?.id) }
    var message by remember(item.id, episode?.id) { mutableStateOf<String?>(null) }
    var askCellular by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    val canDownload = catalog.user?.permissions?.download ?: true

    fun start(allowMetered: Boolean) {
        message = when (val result = graph.downloads.request(active.client, item, episode, canDownload, allowMetered)) {
            Downloads.Request.Started -> null
            Downloads.Request.NotAllowed -> context.getString(R.string.dl_not_allowed)
            Downloads.Request.NoAudio -> context.getString(R.string.dl_no_audio)
            Downloads.Request.NeedsCellularConsent -> { askCellular = true; null }
            is Downloads.Request.NoSpace -> context.getString(R.string.dl_no_space, formatBytes(result.needed))
            Downloads.Request.NotSaved -> notSaved
            is Downloads.Request.FolderLost -> context.getString(R.string.dl_folder_lost_nothing_downloaded, result.name)
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when (record?.state) {
            null -> if (canDownload) OutlinedButton(onClick = { start(false) }, modifier = Modifier.fillMaxWidth().testTag("download")) {
                Icon(Icons.Outlined.Download, null); Text(stringResource(R.string.action_download), Modifier.padding(start = 6.dp))
            }
            DownloadStore.State.QUEUED, DownloadStore.State.RUNNING -> Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("download-progress")) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val fraction = record.fraction()
                    Text(record.error ?: if (fraction != null) stringResource(R.string.dl_downloading_percent, (fraction * 100).toInt()) else stringResource(R.string.dl_downloading), style = MaterialTheme.typography.bodyMedium)
                    if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth()) else LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                IconButton(onClick = { if (!graph.downloads.cancel(record.id)) message = notSaved }, modifier = Modifier.testTag("download-cancel")) { Icon(Icons.Outlined.Close, stringResource(R.string.dl_cancel_download)) }
            }
            DownloadStore.State.COMPLETE -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.dl_downloaded_plays_offline), Modifier.weight(1f).padding(start = 8.dp).testTag("downloaded"))
                TextButton(onClick = { confirmRemove = true }, modifier = Modifier.testTag("download-remove")) { Text(stringResource(R.string.dl_remove)) }
            }
            DownloadStore.State.FAILED -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(record.error ?: stringResource(R.string.dl_failed), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("download-error"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    OutlinedButton(onClick = { if (!graph.downloads.retry(record.id)) message = notSaved }, modifier = Modifier.testTag("download-retry")) { Icon(Icons.Outlined.Refresh, null); Text(stringResource(R.string.action_retry), Modifier.padding(start = 6.dp)) }
                    TextButton(onClick = { if (!graph.downloads.delete(record.id)) message = notSaved }) { Text(stringResource(R.string.dl_discard)) }
                }
            }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("download-message")) }
    }

    if (askCellular) AlertDialog(
        onDismissRequest = { askCellular = false },
        title = { Text(stringResource(R.string.dl_cellular_title)) },
        text = { Text(stringResource(R.string.dl_cellular_message)) },
        confirmButton = { TextButton(onClick = { askCellular = false; start(true) }, modifier = Modifier.testTag("download-cellular-allow")) { Text(stringResource(R.string.action_download)) } },
        dismissButton = { TextButton(onClick = { askCellular = false }) { Text(stringResource(R.string.dl_not_now)) } },
    )
    if (confirmRemove && record != null) RemoveDialog(record.title, onDismiss = { confirmRemove = false }) { confirmRemove = false; if (!remove(graph, record)) message = notSaved }
}

/** Where new downloads go: app storage, or a folder the user chose and can reach from other apps. */
@Composable
fun DownloadLocation(settings: DeviceSettings, change: ((DeviceSettings) -> DeviceSettings) -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
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
            context.getString(R.string.dl_folder_cannot_be_kept)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(if (settings.downloadFolder != null) stringResource(R.string.dl_saved_in_folder, settings.downloadFolderName.toString()) else stringResource(R.string.dl_saved_in_app_storage),
            style = MaterialTheme.typography.bodyLarge, modifier = Modifier.testTag("download-folder"))
        Text(if (settings.downloadFolder != null) stringResource(R.string.dl_folder_visible_to_other_apps)
            else stringResource(R.string.dl_folder_private_to_app),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            OutlinedButton(onClick = { choose.launch(null) }, modifier = Modifier.testTag("choose-download-folder")) {
                Icon(Icons.Outlined.Folder, null); Text(stringResource(R.string.dl_choose_folder), Modifier.padding(start = 6.dp))
            }
            if (settings.downloadFolder != null) TextButton(onClick = {
                val previous = settings.downloadFolder
                change { it.copy(downloadFolder = null, downloadFolderName = null) }
                releaseUnused(previous)
            }, modifier = Modifier.testTag("use-app-storage")) { Text(stringResource(R.string.dl_use_app_storage)) }
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
    val format = part.ebookFormat?.uppercase()
    return when (val opened = graph.downloads.openPart(record, part)) {
        Downloads.Opened.Missing -> context.getString(R.string.dl_ebook_missing)
        is Downloads.Opened.FolderLost -> folderLostMessage(context, opened.name, play = false)
        is Downloads.Opened.Readable -> try {
            context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(opened.uri, ebookType(part.ebookFormat)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            null
        } catch (missing: ActivityNotFoundException) {
            if (format != null) context.getString(R.string.dl_no_app_opens_format, format) else context.getString(R.string.dl_no_app_opens_this_kind)
        }
    }
}

private fun folderLostMessage(context: Context, name: String, play: Boolean) =
    context.getString(if (play) R.string.dl_folder_lost_choose_again_play else R.string.dl_folder_lost_choose_again_open, name)

/** Joins folder names with the localized "A or B" / "A and B" pattern. */
private fun joinNames(context: Context, names: List<String>, pattern: Int) = names.reduceOrNull { first, second -> context.getString(pattern, first, second) }.orEmpty()

private fun remove(graph: com.audiobookshelf.android.AppGraph, record: DownloadStore.Record): Boolean {
    val now = graph.playback.state.value.now
    if (now != null && now.local && now.itemId == record.itemId && now.episodeId == record.episodeId) graph.playback.close()
    return graph.downloads.delete(record.id)
}

@Composable
private fun RemoveDialog(title: String, onDismiss: () -> Unit, onConfirm: () -> Unit) = AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text(stringResource(R.string.dl_remove_title)) },
    text = { Text(stringResource(R.string.dl_remove_message, title)) },
    confirmButton = { TextButton(onClick = onConfirm, modifier = Modifier.testTag("confirm-delete-download")) { Text(stringResource(R.string.dl_remove)) } },
    dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.dl_keep)) } },
)

/** Everything downloaded for the active account; works without the server. */
@Composable
fun DownloadsScreen(active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onRead: (Route) -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val notSaved = stringResource(R.string.dl_not_saved)
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
        val names = joinNames(context, lost.mapNotNull { it.folderName }.distinct(), R.string.dl_names_or)
        message = try {
            if (graph.downloads.regainFolder(tree)) null else context.getString(R.string.dl_not_that_folder, names)
        } catch (failure: SecurityException) { context.getString(R.string.dl_folder_access_not_kept) }
        looked++
    }
    if (records.isEmpty()) {
        MessageState(stringResource(R.string.dl_no_downloads), stringResource(R.string.dl_no_downloads_message), Modifier.padding(padding), icon = Icons.Outlined.DownloadForOffline, tag = "downloads-empty")
        return
    }
    // Notices stay above the list: an item inserted above the first visible row would be scrolled out of view.
    Column(Modifier.fillMaxSize().padding(padding)) {
        if (lost.isNotEmpty()) {
            val names = joinNames(context, lost.mapNotNull { it.folderName }.distinct(), R.string.dl_names_and)
            Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp).testTag("folder-access-lost"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.dl_access_removed_title, names), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                Text(pluralStringResource(R.plurals.dl_downloads_kept_there, lost.size, lost.size, names), style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = { regain.launch(null) }, modifier = Modifier.testTag("choose-folder-again")) { Text(stringResource(R.string.dl_choose_again, names)) }
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
                Column(Modifier.fillMaxWidth().testTag(tag), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Cover(File(record.directory, "cover.jpg").takeIf { it.exists() }, record.title, Modifier.size(56.dp), podcast = record.mediaType == "podcast")
                        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                            Text(record.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            if (record.author.isNotBlank()) Text(record.author, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            when (record.state) {
                                DownloadStore.State.COMPLETE -> if (record.id in missing) Text(stringResource(R.string.dl_some_files_missing), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                    else Text(formatBytes(record.bytes.takeIf { it > 0 } ?: record.total ?: 0).let { size -> record.folderName?.let { stringResource(R.string.dl_size_in_folder, size, it) } ?: size }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                DownloadStore.State.FAILED -> Text(record.error ?: stringResource(R.string.dl_failed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                else -> {
                                    val fraction = record.fraction()
                                    if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) else LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 4.dp))
                                    Text(record.error ?: if (fraction != null) stringResource(R.string.dl_downloading_percent, (fraction * 100).toInt()) else stringResource(R.string.dl_downloading), style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                    }
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        val readable = record.ebook?.takeIf { record.state == DownloadStore.State.COMPLETE && it.ebookFormat == "pdf" }
                        if (readable != null) IconButton(
                            onClick = { onRead(Route.Reader(record.itemId, readable.ebookFileId!!, supplementary = false, title = record.title, downloadId = record.id)) },
                            modifier = Modifier.testTag("read-offline-$key"),
                        ) { Icon(Icons.AutoMirrored.Outlined.MenuBook, stringResource(R.string.action_read, record.title)) }
                        if (record.state == DownloadStore.State.COMPLETE && record.ebook != null && record.id !in missing) IconButton(
                            onClick = { message = openElsewhere(context, graph, record); looked++ },
                            modifier = Modifier.testTag("open-elsewhere-$key"),
                        ) { Icon(Icons.AutoMirrored.Outlined.OpenInNew, stringResource(R.string.dl_open_in_another_app, record.title)) }
                        when {
                            record.id in missing -> OutlinedButton(onClick = { message = if (graph.downloads.retry(record.id)) null else notSaved }, modifier = Modifier.testTag("download-retry-$key")) { Icon(Icons.Outlined.Refresh, stringResource(R.string.dl_download_again_named, record.title)); Text(stringResource(R.string.action_download), Modifier.padding(start = 6.dp)) }
                            record.state == DownloadStore.State.COMPLETE -> if (record.audio.isNotEmpty()) OutlinedButton(
                                onClick = {
                                    message = when {
                                        graph.downloads.folderLost(record) -> folderLostMessage(context, record.folderName ?: context.getString(R.string.dl_the_chosen_folder), play = true)
                                        graph.downloads.missing(record) -> context.getString(R.string.dl_files_missing_play)
                                        else -> { graph.playback.play(graph.downloads.localSource(record, catalog.progressFor(record.itemId, record.episodeId))); null }
                                    }
                                    looked++
                                },
                                modifier = Modifier.testTag("play-offline-$key"),
                            ) { Icon(Icons.Filled.PlayArrow, stringResource(R.string.dl_play_named, record.title)); Text(stringResource(R.string.action_play), Modifier.padding(start = 6.dp)) }
                            record.state == DownloadStore.State.FAILED -> OutlinedButton(onClick = { message = if (graph.downloads.retry(record.id)) null else notSaved }, modifier = Modifier.testTag("download-retry-$key")) { Icon(Icons.Outlined.Refresh, stringResource(R.string.dl_retry_named, record.title)); Text(stringResource(R.string.action_retry), Modifier.padding(start = 6.dp)) }
                            else -> TextButton(onClick = { message = if (graph.downloads.cancel(record.id)) null else notSaved }, modifier = Modifier.testTag("cancel-download-$key")) { Icon(Icons.Outlined.Close, stringResource(R.string.dl_cancel_named, record.title)); Text(stringResource(R.string.action_cancel), Modifier.padding(start = 6.dp)) }
                        }
                        if (record.state != DownloadStore.State.QUEUED && record.state != DownloadStore.State.RUNNING) {
                            IconButton(onClick = { removing = record }, modifier = Modifier.testTag("delete-download-$key")) { Icon(Icons.Outlined.Delete, stringResource(R.string.dl_remove_named, record.title)) }
                        }
                    }
                    }
            }
        }
    }
    removing?.let { record -> RemoveDialog(record.title, onDismiss = { removing = null }) { removing = null; message = if (remove(graph, record)) null else notSaved } }
}
