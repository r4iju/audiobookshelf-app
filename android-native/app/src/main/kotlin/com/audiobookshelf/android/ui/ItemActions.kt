package com.audiobookshelf.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.RssFeed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.R
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.EreaderDevice
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.RssFeed
import com.audiobookshelf.core.RssFeedMeta
import kotlinx.coroutines.launch

private val SLUG = Regex("[A-Za-z0-9_-]+")

private fun Exception.explanation(context: Context): String =
    (this as? ApiError.Http)?.takeIf { it.status == 400 }?.body?.takeIf { it.isNotBlank() && !it.trimStart().startsWith("{") }
        ?: message ?: context.getString(R.string.item_something_went_wrong)

/**
 * The item's RSS feed, as the server permits: administrators open and close it, and anyone can see
 * and copy the address of a feed that is already open. Only titles with audio or episodes can have a feed.
 */
@Composable
fun FeedButton(item: LibraryItem, active: SessionState.Active, catalog: CatalogModel) {
    val graph = LocalContext.current.graph
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var feed by remember(item.id) { mutableStateOf(item.rssFeed) }
    var showing by remember { mutableStateOf(false) }
    val admin = catalog.user?.isAdmin == true
    val audible = if (item.isPodcast) item.media.episodes.isNotEmpty() else item.hasAudio
    if (!audible || (!admin && feed == null)) return

    OutlinedButton(onClick = { showing = true }, modifier = Modifier.fillMaxWidth().testTag("rss-feed")) {
        Icon(Icons.Outlined.RssFeed, null, Modifier.size(18.dp))
        Text(stringResource(if (feed != null) R.string.item_rss_feed_is_open else R.string.item_open_rss_feed), Modifier.padding(start = 8.dp))
    }
    if (!showing) return

    var slug by remember { mutableStateOf(item.id) }
    var preventIndexing by remember { mutableStateOf(true) }
    var ownerName by remember { mutableStateOf("") }
    var ownerEmail by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var copied by remember { mutableStateOf(false) }

    fun run(action: suspend () -> Unit) {
        working = true; error = null
        scope.launch {
            try { action() } catch (failure: Exception) {
                error = failure.explanation(context); graph.accounts.handle(failure)
            } finally { working = false }
        }
    }

    val open = feed
    AlertDialog(
        onDismissRequest = { if (!working) showing = false },
        icon = { Icon(Icons.Outlined.RssFeed, null) },
        title = { Text(stringResource(if (open != null) R.string.item_rss_feed else R.string.item_open_rss_feed)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (open != null) {
                    val url = active.client.feedUrl(open)
                    val clipLabel = stringResource(R.string.item_rss_feed)
                    Text(stringResource(R.string.item_feed_subscribe_at), style = MaterialTheme.typography.bodyMedium)
                    Text(url, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.testTag("feed-url"))
                    TextButton(onClick = {
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(clipLabel, url))
                        copied = true
                    }, modifier = Modifier.testTag("feed-copy")) { Text(stringResource(if (copied) R.string.item_copied else R.string.item_copy_address)) }
                    if (open.meta.preventIndexing) Text(stringResource(R.string.item_hidden_from_directories), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Text(stringResource(R.string.item_feed_public_warning), style = MaterialTheme.typography.bodyMedium)
                    OutlinedTextField(slug, { slug = it.trim() }, label = { Text(stringResource(R.string.item_feed_name)) }, singleLine = true,
                        isError = slug.isNotEmpty() && !SLUG.matches(slug),
                        supportingText = { Text(stringResource(R.string.item_feed_name_rule)) },
                        modifier = Modifier.fillMaxWidth().testTag("feed-slug"))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        val hideLabel = stringResource(R.string.item_hide_from_directories)
                        Text(hideLabel, Modifier.weight(1f))
                        Switch(preventIndexing, { preventIndexing = it }, modifier = Modifier.testTag("feed-prevent-indexing").semantics { contentDescription = hideLabel })
                    }
                    if (!preventIndexing) {
                        OutlinedTextField(ownerName, { ownerName = it }, label = { Text(stringResource(R.string.item_owner_name)) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("feed-owner-name"))
                        OutlinedTextField(ownerEmail, { ownerEmail = it.trim() }, label = { Text(stringResource(R.string.item_owner_email)) }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth().testTag("feed-owner-email"))
                    }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("feed-error")) }
            }
        },
        confirmButton = {
            if (open == null) TextButton(
                onClick = {
                    run {
                        val meta = if (preventIndexing) RssFeedMeta(preventIndexing = true)
                            else RssFeedMeta(preventIndexing = false, ownerName = ownerName.ifBlank { null }, ownerEmail = ownerEmail.ifBlank { null })
                        feed = active.client.openFeed(item.id, slug, meta)
                    }
                },
                enabled = !working && SLUG.matches(slug),
                modifier = Modifier.testTag("feed-open"),
            ) { Text(stringResource(R.string.item_open_feed)) }
            else if (admin) TextButton(
                onClick = { run { active.client.closeFeed(open.id); feed = null; showing = false } },
                enabled = !working,
                modifier = Modifier.testTag("feed-close"),
            ) { Text(stringResource(R.string.item_close_feed), color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = { showing = false }, enabled = !working) { Text(stringResource(if (open != null) R.string.item_done else R.string.action_cancel)) } },
    )
}

/** Emails the title's ebook to an e-reader the server has configured for this user. */
@Composable
fun SendEbookButton(item: LibraryItem, active: SessionState.Active) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    var devices by remember(item.id) { mutableStateOf<List<EreaderDevice>>(emptyList()) }
    var choosing by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var sent by remember(item.id) { mutableStateOf<String?>(null) }
    var error by remember(item.id) { mutableStateOf<String?>(null) }
    if (item.primaryEbook == null) return
    // Devices are read when the title is shown, so a device the administrator removed is not offered.
    LaunchedEffect(item.id, active.client) {
        devices = runCatching { active.client.authorize().ereaderDevices }.getOrElse { graph.accounts.handle(it); emptyList() }
    }
    if (devices.isEmpty()) return

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        OutlinedButton(onClick = { choosing = true; error = null }, enabled = !sending, modifier = Modifier.fillMaxWidth().testTag("send-ebook")) {
            Icon(Icons.AutoMirrored.Outlined.Send, null, Modifier.size(18.dp))
            Text(stringResource(if (sending) R.string.item_sending else R.string.item_send_to_ereader), Modifier.padding(start = 8.dp))
        }
        sent?.let { Text(stringResource(R.string.item_sent_to, it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("send-ebook-sent")) }
        error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("send-ebook-error")) }
    }
    if (choosing) AlertDialog(
        onDismissRequest = { choosing = false },
        icon = { Icon(Icons.AutoMirrored.Outlined.Send, null) },
        title = { Text(stringResource(R.string.item_send_to_ereader)) },
        text = {
            Column {
                Text(stringResource(R.string.item_send_ebook_explanation), style = MaterialTheme.typography.bodyMedium)
                devices.forEach { device ->
                    TextButton(onClick = {
                        choosing = false; sending = true; sent = null; error = null
                        scope.launch {
                            try {
                                active.client.sendEbook(item.id, device.name)
                                sent = device.name
                            } catch (failure: Exception) {
                                error = if (failure is ApiError.Http && failure.status == 404) context.getString(R.string.item_ereader_or_ebook_gone, device.name)
                                    else context.getString(R.string.item_not_sent_to, device.name, failure.explanation(context))
                                graph.accounts.handle(failure)
                            } finally { sending = false }
                        }
                    }, modifier = Modifier.fillMaxWidth().testTag("send-device-${device.name}")) { Text(device.name, Modifier.fillMaxWidth()) }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = { choosing = false }) { Text(stringResource(R.string.action_cancel)) } },
    )
}
