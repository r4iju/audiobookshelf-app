package com.audiobookshelf.android.ui

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
                IconButton(onClick = { graph.downloads.delete(record.id) }, modifier = Modifier.testTag("download-cancel")) { Icon(Icons.Outlined.Close, "Cancel download") }
            }
            DownloadStore.State.COMPLETE -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                Text("Downloaded · plays offline", Modifier.weight(1f).padding(start = 8.dp).testTag("downloaded"))
                TextButton(onClick = { confirmRemove = true }, modifier = Modifier.testTag("download-remove")) { Text("Remove") }
            }
            DownloadStore.State.FAILED -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(record.error ?: "The download failed.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("download-error"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { graph.downloads.retry(record.id) }, modifier = Modifier.testTag("download-retry")) { Icon(Icons.Outlined.Refresh, null); Text("Retry", Modifier.padding(start = 6.dp)) }
                    TextButton(onClick = { graph.downloads.delete(record.id) }) { Text("Discard") }
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
    if (confirmRemove && record != null) RemoveDialog(record.title, onDismiss = { confirmRemove = false }) { confirmRemove = false; remove(graph, record) }
}

private fun remove(graph: com.audiobookshelf.android.AppGraph, record: DownloadStore.Record) {
    val now = graph.playback.state.value.now
    if (now != null && now.local && now.itemId == record.itemId && now.episodeId == record.episodeId) graph.playback.close()
    graph.downloads.delete(record.id)
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
fun DownloadsScreen(active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues) {
    val graph = LocalContext.current.graph
    val all by graph.downloads.records.collectAsState()
    val records = all.filter { it.account == active.client.account }.sortedByDescending { it.createdAt }
    var removing by remember { mutableStateOf<DownloadStore.Record?>(null) }
    if (records.isEmpty()) {
        MessageState("No downloads", "Download books or episodes from their page to listen without a connection.", Modifier.padding(padding), tag = "downloads-empty")
        return
    }
    LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("downloads"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
                        DownloadStore.State.COMPLETE -> Text(formatBytes(record.bytes.takeIf { it > 0 } ?: record.total ?: 0), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        DownloadStore.State.FAILED -> Text(record.error ?: "The download failed.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                        else -> {
                            val fraction = record.fraction()
                            if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) else LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 4.dp))
                            record.error?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
                when (record.state) {
                    DownloadStore.State.COMPLETE -> IconButton(
                        onClick = { graph.playback.play(graph.downloads.localSource(record, catalog.progressFor(record.itemId, record.episodeId))) },
                        modifier = Modifier.testTag("play-offline-$key"),
                    ) { Icon(Icons.Filled.PlayArrow, "Play ${record.title}") }
                    DownloadStore.State.FAILED -> IconButton(onClick = { graph.downloads.retry(record.id) }, modifier = Modifier.testTag("download-retry-$key")) { Icon(Icons.Outlined.Refresh, "Retry ${record.title}") }
                    else -> IconButton(onClick = { graph.downloads.delete(record.id) }, modifier = Modifier.testTag("cancel-download-$key")) { Icon(Icons.Outlined.Close, "Cancel ${record.title}") }
                }
                if (record.state != DownloadStore.State.QUEUED && record.state != DownloadStore.State.RUNNING) {
                    IconButton(onClick = { removing = record }, modifier = Modifier.testTag("delete-download-$key")) { Icon(Icons.Outlined.Delete, "Remove ${record.title}") }
                }
            }
        }
    }
    removing?.let { record -> RemoveDialog(record.title, onDismiss = { removing = null }) { removing = null; remove(graph, record) } }
}
