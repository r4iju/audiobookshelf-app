package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.playback.PlaybackEngine
import com.audiobookshelf.android.playback.PlayerState
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.Bookmark
import com.audiobookshelf.core.SleepTimer
import kotlinx.coroutines.launch

private val sleepPresets = listOf(5, 10, 15, 30, 45, 60, 90)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SleepSheet(engine: PlaybackEngine, state: PlayerState, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.sleep_timer), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            val remaining = state.sleepRemaining
            if (remaining != null) {
                Text(if (state.sleepEndOfChapter) stringResource(R.string.pl_sleep_stops_end_of_chapter, formatClock(remaining)) else stringResource(R.string.pl_sleep_stops_in, formatClock(remaining)),
                    style = MaterialTheme.typography.bodyLarge)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { engine.adjustSleep(-300.0) }, modifier = Modifier.testTag("sleep-subtract")) { Text(stringResource(R.string.pl_sleep_minus_minutes, 5)) }
                    OutlinedButton(onClick = { engine.adjustSleep(300.0); onDismiss() }, modifier = Modifier.testTag("sleep-add")) { Text(stringResource(R.string.pl_sleep_plus_minutes, 5)) }
                    Button(onClick = { engine.cancelSleep(); onDismiss() }, modifier = Modifier.testTag("sleep-cancel")) { Text(stringResource(R.string.pl_sleep_turn_off)) }
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                sleepPresets.forEach { minutes ->
                    FilledTonalButton(onClick = { engine.startSleep(SleepTimer.Mode.Duration(minutes * 60.0)); onDismiss() }, modifier = Modifier.testTag("sleep-$minutes")) { Text(stringResource(R.string.pl_sleep_minutes, minutes)) }
                }
                if (state.now?.chapters?.isNotEmpty() == true) {
                    FilledTonalButton(onClick = { engine.startSleep(SleepTimer.Mode.EndOfChapter); onDismiss() }, modifier = Modifier.testTag("sleep-end-of-chapter")) { Text(stringResource(R.string.end_of_chapter)) }
                }
            }
        }
    }
}

/** Server bookmarks for the playing item; changes are saved before the list updates. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookmarksSheet(client: ApiClient, itemId: String, position: Double, onSeek: (Double) -> Unit, onFailure: (Throwable) -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var bookmarks by remember { mutableStateOf<List<Bookmark>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<Bookmark?>(null) }
    var adding by remember { mutableStateOf(false) }
    LaunchedEffect(itemId) {
        runCatching { client.me() }.onSuccess { me -> bookmarks = me.bookmarks.filter { it.libraryItemId == itemId }.sortedBy { it.time } }
            .onFailure { error = it.localizedMessage; onFailure(it) }
    }
    fun mutate(action: suspend () -> List<Bookmark>) {
        scope.launch {
            runCatching { action() }.onSuccess { bookmarks = it.sortedBy { mark -> mark.time }; error = null }
                .onFailure { error = it.localizedMessage?.let { message -> context.getString(R.string.pl_bookmark_not_saved_reason, message) } ?: context.getString(R.string.pl_bookmark_not_saved); onFailure(it) }
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.bookmarks), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Button(onClick = { adding = true }, modifier = Modifier.testTag("add-bookmark")) { Text(stringResource(R.string.pl_bookmark_add_at, formatClock(position))) }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("bookmark-error")) }
            val list = bookmarks
            when {
                list == null && error == null -> CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
                list.isNullOrEmpty() -> Text(stringResource(R.string.no_bookmarks), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("bookmarks-empty"))
                else -> LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    itemsIndexed(list) { index, mark ->
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f).clickable(role = Role.Button, onClickLabel = stringResource(R.string.pl_bookmark_go_to)) { onSeek(mark.time); onDismiss() }
                                .padding(vertical = 10.dp).testTag("bookmark-$index")) {
                                Text(mark.title.ifBlank { stringResource(R.string.pl_bookmark_default) }, style = MaterialTheme.typography.bodyLarge)
                                Text(formatClock(mark.time), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            IconButton(onClick = { editing = mark }, modifier = Modifier.testTag("edit-bookmark-$index")) { Icon(Icons.Outlined.Edit, stringResource(R.string.pl_bookmark_rename_named, mark.title)) }
                            IconButton(onClick = {
                                mutate { client.deleteBookmark(itemId, mark.time); list.filterNot { it.time == mark.time } }
                            }, modifier = Modifier.testTag("delete-bookmark-$index")) { Icon(Icons.Outlined.Delete, stringResource(R.string.pl_bookmark_delete_named, mark.title)) }
                        }
                    }
                }
            }
        }
    }
    val target = editing
    if (adding || target != null) {
        val defaultTitle = stringResource(R.string.pl_bookmark_at, formatClock(position))
        val untitled = stringResource(R.string.pl_bookmark_default)
        var title by remember(target, adding) { mutableStateOf(target?.title ?: defaultTitle) }
        AlertDialog(
            onDismissRequest = { adding = false; editing = null },
            title = { Text(if (target != null) stringResource(R.string.pl_bookmark_rename) else stringResource(R.string.pl_bookmark_new)) },
            text = { OutlinedTextField(title, { title = it }, singleLine = true, label = { Text(stringResource(R.string.pl_bookmark_title_field)) }, modifier = Modifier.testTag("bookmark-title")) },
            confirmButton = {
                TextButton(onClick = {
                    val name = title.trim().ifEmpty { untitled }
                    val current = bookmarks.orEmpty()
                    if (target != null) mutate { val saved = client.saveBookmark(itemId, target.time, name, editing = true); current.map { if (it.time == target.time) saved else it } }
                    else { val time = position; mutate { current + client.saveBookmark(itemId, time, name, editing = false) } }
                    adding = false; editing = null
                }, modifier = Modifier.testTag("save-bookmark")) { Text(stringResource(R.string.action_save)) }
            },
            dismissButton = { TextButton(onClick = { adding = false; editing = null }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}
