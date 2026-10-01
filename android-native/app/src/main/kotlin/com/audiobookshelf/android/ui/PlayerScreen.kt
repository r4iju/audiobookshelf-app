package com.audiobookshelf.android.ui

import com.audiobookshelf.android.data.CellularPolicy
import androidx.compose.material3.AlertDialog
import android.net.ConnectivityManager
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Forward30
import androidx.compose.material.icons.filled.Forward5
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Replay30
import androidx.compose.material.icons.filled.Replay5
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.android.playback.PlayerState
import com.audiobookshelf.android.playback.itemKey
import com.audiobookshelf.core.Chapter

private val speedPresets = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)

/** Full-screen player. Positions are book-wide; the slider covers the current chapter when there are chapters. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(onCollapse: () -> Unit, onClosed: () -> Unit) {
    val engine = LocalContext.current.graph.playback
    val state by engine.state.collectAsState()
    val now = state.now
    var speedSheet by remember { mutableStateOf(false) }
    var tool by remember { mutableStateOf<String?>(null) }
    val graph = LocalContext.current.graph
    val client = graph.accounts.activeClient

    Surface(Modifier.fillMaxSize().testTag("player-screen")) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onCollapse, modifier = Modifier.testTag("player-collapse")) { Icon(Icons.Outlined.KeyboardArrowDown, "Minimize player") }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { engine.close(); onClosed() }, modifier = Modifier.testTag("player-close")) { Icon(Icons.Outlined.Close, "Stop and close player") }
            }
            if (now == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (state.loading) CircularProgressIndicator() else Text("Nothing is playing", style = MaterialTheme.typography.bodyLarge)
                }
                return@Column
            }
            val chapterIndex = now.chapters.indexOfLast { it.start <= state.position + 0.0005 }
            val chapter = now.chapters.getOrNull(chapterIndex)
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item { Cover(now.coverUrl, now.title, Modifier.widthIn(max = 300.dp).fillMaxWidth(0.7f), podcast = now.isPodcast) }
                item {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(now.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                            maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() })
                        if (now.author.isNotBlank()) Text(now.author, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                        chapter?.let { Text(it.title.ifBlank { "Chapter ${chapterIndex + 1}" }, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 4.dp)) }
                    }
                }
                item { Timeline(state, chapter, onSeek = engine::seekTo) }
                item {
                    when {
                        state.error != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(state.error.orEmpty(), color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center, modifier = Modifier.testTag("player-error"))
                            Button(onClick = engine::retry, modifier = Modifier.testTag("player-retry")) { Text("Try again") }
                        }
                        state.finished -> Text("Finished", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.testTag("player-finished"))
                    }
                }
                item { Controls(state, engine::previousChapter, { engine.jump(false) }, engine::toggle, { engine.jump(true) }, engine::nextChapter, hasChapters = now.chapters.isNotEmpty()) }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { speedSheet = true }, modifier = Modifier.testTag("player-speed")) { Text("Speed ${formatSpeed(state.speed)}") }
                        val remaining = state.sleepRemaining
                        TextButton(onClick = { tool = "sleep" }, modifier = Modifier.testTag("player-sleep")) {
                            Icon(Icons.Outlined.Bedtime, if (remaining != null) "Sleep timer" else null, Modifier.size(18.dp))
                            if (remaining == null) Text("Sleep", Modifier.padding(start = 6.dp))
                        }
                        if (remaining != null) Text(formatClock(remaining), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.semantics { stateDescription = "Sleep timer" }.testTag("sleep-remaining"))
                        if (client != null) TextButton(onClick = { tool = "bookmarks" }, modifier = Modifier.testTag("player-bookmarks")) {
                            Icon(Icons.Outlined.BookmarkBorder, null, Modifier.size(18.dp))
                            Text("Bookmarks", Modifier.padding(start = 6.dp))
                        }
                    }
                }
                if (now.chapters.isNotEmpty()) {
                    item { Text("Chapters", style = MaterialTheme.typography.titleMedium, modifier = Modifier.fillMaxWidth().semantics { heading() }) }
                    itemsIndexed(now.chapters) { index, item -> ChapterRow(index, item, current = index == chapterIndex) { engine.seekChapter(index) } }
                }
            }
        }
    }
    when (tool) {
        "sleep" -> SleepSheet(engine, state) { tool = null }
        "bookmarks" -> if (now != null && client != null) BookmarksSheet(client, now.itemId, state.position, engine::seekTo, graph.accounts::handle) { tool = null }
    }
    if (speedSheet) {
        ModalBottomSheet(onDismissRequest = { speedSheet = false }) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 8.dp).padding(bottom = 24.dp)) {
                Text("Playback speed", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                Text(formatSpeed(state.speed), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(vertical = 8.dp))
                Slider(value = state.speed, onValueChange = { engine.setSpeed((it * 20).toInt() / 20f) }, valueRange = 0.5f..3f, modifier = Modifier.testTag("speed-slider"))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
                    speedPresets.forEach { speed ->
                        TextButton(onClick = { engine.setSpeed(speed) }, modifier = Modifier.weight(1f).testTag("speed-$speed")) { Text(formatSpeed(speed), maxLines = 1) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Timeline(state: PlayerState, chapter: Chapter?, onSeek: (Double) -> Unit) {
    val now = state.now ?: return
    val start = chapter?.start ?: 0.0
    val end = chapter?.end?.takeIf { it > start } ?: now.duration
    var dragging by remember { mutableStateOf<Float?>(null) }
    val fraction = dragging ?: ((state.position - start) / (end - start)).toFloat().coerceIn(0f, 1f)
    Column(Modifier.fillMaxWidth()) {
        Slider(
            value = fraction,
            onValueChange = { dragging = it },
            onValueChangeFinished = { dragging?.let { onSeek(start + it * (end - start)) }; dragging = null },
            modifier = Modifier.testTag("player-slider").semantics { stateDescription = "${formatClock(state.position)} of ${formatClock(now.duration)}" },
        )
        Row(Modifier.fillMaxWidth()) {
            Text(formatClock(state.position), style = MaterialTheme.typography.labelMedium, modifier = Modifier.testTag("player-position"))
            Spacer(Modifier.weight(1f))
            if (state.buffering) Text("Buffering", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text("-" + formatClock((now.duration - state.position).coerceAtLeast(0.0)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Controls(state: PlayerState, onPrevious: () -> Unit, onBack: () -> Unit, onToggle: () -> Unit, onForward: () -> Unit, onNext: () -> Unit, hasChapters: Boolean) {
    val settings by LocalContext.current.graph.settings.settings.collectAsState()
    val haptic = rememberHaptic()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { haptic(); onPrevious() }, enabled = hasChapters, modifier = Modifier.testTag("previous-chapter")) { Icon(Icons.Filled.SkipPrevious, "Previous chapter") }
        IconButton(onClick = { haptic(); onBack() }, modifier = Modifier.size(56.dp).testTag("jump-back")) { Icon(jumpIcon(false, settings.jumpBackwardsTime), jumpDescription(false, settings.jumpBackwardsTime), Modifier.size(32.dp)) }
        Box(Modifier.testTag(if (state.playing) "player-playing" else "player-paused")) {
            FilledIconButton(onClick = { haptic(); onToggle() }, modifier = Modifier.size(72.dp).testTag("play-pause"), colors = IconButtonDefaults.filledIconButtonColors()) {
                if (state.loading) CircularProgressIndicator(Modifier.size(28.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 3.dp)
                else Icon(if (state.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (state.playing) "Pause" else "Play", Modifier.size(40.dp))
            }
        }
        IconButton(onClick = { haptic(); onForward() }, modifier = Modifier.size(56.dp).testTag("jump-forward")) { Icon(jumpIcon(true, settings.jumpForwardTime), jumpDescription(true, settings.jumpForwardTime), Modifier.size(32.dp)) }
        IconButton(onClick = { haptic(); onNext() }, enabled = hasChapters, modifier = Modifier.testTag("next-chapter")) { Icon(Icons.Filled.SkipNext, "Next chapter") }
    }
}

private fun jumpIcon(forward: Boolean, seconds: Int): ImageVector = when (seconds) {
    5 -> if (forward) Icons.Filled.Forward5 else Icons.Filled.Replay5
    10 -> if (forward) Icons.Filled.Forward10 else Icons.Filled.Replay10
    30 -> if (forward) Icons.Filled.Forward30 else Icons.Filled.Replay30
    else -> if (forward) Icons.Filled.FastForward else Icons.Filled.FastRewind
}

fun jumpDescription(forward: Boolean, seconds: Int): String {
    val amount = if (seconds < 60) "$seconds seconds" else (seconds / 60).let { if (it == 1) "1 minute" else "$it minutes" }
    return "Jump ${if (forward) "forward" else "back"} $amount"
}

@Composable
private fun ChapterRow(index: Int, chapter: Chapter, current: Boolean, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).semantics { selected = current }.padding(vertical = 12.dp).testTag("player-chapter-$index"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(chapter.title.ifBlank { "Chapter ${index + 1}" }, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f),
                color = if (current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, fontWeight = if (current) FontWeight.SemiBold else null)
            Text(formatClock(chapter.start), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        HorizontalDivider()
    }
}

/** Compact player above the bottom navigation; tapping it opens the full player. */
@Composable
fun MiniPlayer(onOpen: () -> Unit) {
    val engine = LocalContext.current.graph.playback
    val state by engine.state.collectAsState()
    val jumpBack = LocalContext.current.graph.settings.settings.collectAsState().value.jumpBackwardsTime
    if (state.unsavedListening && (state.now == null || state.error == null)) Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
        Text("Some listening is not saved on this device yet. It is kept and saved as soon as storage allows.",
            style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("listening-unsaved"))
    }
    val now = state.now ?: return
    Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth()) {
        Column {
            val chapter = now.chapters.lastOrNull { it.start <= state.position + 0.0005 }
            val (start, end) = chapter?.let { it.start to it.end } ?: (0.0 to now.duration)
            LinearProgressIndicator(progress = { ((state.position - start) / (end - start).coerceAtLeast(0.001)).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(2.dp))
            Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.weight(1f).clickable(role = Role.Button, onClickLabel = "Open player", onClick = onOpen).padding(start = 12.dp, top = 8.dp, bottom = 8.dp).testTag("mini-player"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(now.coverUrl, now.title, Modifier.width(44.dp), podcast = now.isPodcast)
                    Column(Modifier.padding(horizontal = 12.dp)) {
                        Text(now.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(state.error?.let { "Playback stopped" } ?: chapter?.title?.takeIf { it.isNotBlank() } ?: now.author, style = MaterialTheme.typography.bodySmall,
                            color = if (state.error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                IconButton(onClick = { engine.jump(false) }, modifier = Modifier.testTag("mini-jump-back")) { Icon(jumpIcon(false, jumpBack), jumpDescription(false, jumpBack)) }
                Box(Modifier.testTag(if (state.playing) "mini-playing" else "mini-paused")) {
                    IconButton(onClick = engine::toggle, modifier = Modifier.testTag("mini-play-pause")) {
                        Icon(if (state.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (state.playing) "Pause" else "Play")
                    }
                }
            }
        }
    }
}

fun formatSpeed(speed: Float): String = "%.2f".format(speed).trimEnd('0').let { if (it.endsWith('.')) it + "0" else it } + "×"

/**
 * Starts or resumes an item and opens the player once the media is loaded. An open failure stays on
 * the item screen with its reason, because there is nothing to show in a player.
 */
@Composable
fun PlayButton(source: () -> PlaySource, itemId: String, episodeId: String?, onOpened: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val engine = context.graph.playback
    val state by engine.state.collectAsState()
    val haptic = rememberHaptic()
    var waiting by remember(itemId, episodeId) { mutableStateOf(false) }
    var askCellular by remember { mutableStateOf<PlaySource?>(null) }
    var refused by remember(itemId, episodeId) { mutableStateOf(false) }
    val start: (PlaySource) -> Unit = { waiting = true; refused = false; engine.play(it) }
    val key = itemKey(itemId, episodeId)
    val loadedHere = state.now?.let { it.itemId == itemId && it.episodeId == episodeId } == true
    LaunchedEffect(waiting, loadedHere, state.openError) {
        if (!waiting) return@LaunchedEffect
        if (loadedHere) { waiting = false; onOpened() }
        else if (state.openError?.first == key) waiting = false
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Button(
            onClick = {
                haptic()
                val chosen = source()
                val metered = context.getSystemService(ConnectivityManager::class.java)?.isActiveNetworkMetered == true
                if (chosen !is PlaySource.Stream || !metered) start(chosen)
                else when (context.graph.settings.current.streamingUsingCellular) {
                    CellularPolicy.ALWAYS -> start(chosen)
                    CellularPolicy.ASK -> askCellular = chosen
                    CellularPolicy.NEVER -> refused = true
                }
            },
            enabled = !waiting,
            modifier = Modifier.fillMaxWidth().testTag("play"),
        ) {
            if (waiting) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            else {
                Icon(Icons.Filled.PlayArrow, null)
                Text(if (loadedHere && state.playing) "Playing" else if (loadedHere) "Resume" else "Play", Modifier.padding(start = 6.dp))
            }
        }
        if (refused) Text("Streaming on mobile data is turned off in Settings. Connect to Wi-Fi or download this title first.",
            color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("play-cellular-refused"))
        state.openError?.takeIf { it.first == key && !waiting }?.let { (_, message) ->
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("play-error"))
        }
    }
    askCellular?.let { pending ->
        AlertDialog(
            onDismissRequest = { askCellular = null },
            title = { Text("Stream on mobile data?") },
            text = { Text("You are on a metered connection. You can change this in Settings.") },
            confirmButton = { TextButton(onClick = { askCellular = null; start(pending) }, modifier = Modifier.testTag("play-cellular-allow")) { Text("Stream") } },
            dismissButton = { TextButton(onClick = { askCellular = null }) { Text("Not now") } },
        )
    }
}
