package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.audiobookshelf.android.data.CellularPolicy
import com.audiobookshelf.android.data.DeviceSettings
import androidx.compose.material3.AlertDialog
import android.net.ConnectivityManager
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.FlowRow
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
    var castSheet by remember { mutableStateOf(false) }
    var tool by remember { mutableStateOf<String?>(null) }
    val graph = LocalContext.current.graph
    val client = graph.accounts.activeClient
    val settings by graph.settings.settings.collectAsState()
    var preferenceError by remember { mutableStateOf<String?>(null) }
    val saveFailed = stringResource(R.string.set_settings_not_saved)

    Surface(Modifier.fillMaxSize().testTag("player-screen")) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onCollapse, modifier = Modifier.testTag("player-collapse")) { Icon(Icons.Outlined.KeyboardArrowDown, stringResource(R.string.pl_minimize_player)) }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = {
                    preferenceError = try { graph.settings.update { it.copy(lockUi = !it.lockUi) }; null }
                    catch (_: java.io.IOException) { saveFailed }
                }, modifier = Modifier.testTag("player-lock")) {
                    Text(stringResource(if (settings.lockUi) R.string.pl_unlock else R.string.pl_lock))
                }
                CastButton(graph.casting) { castSheet = true }
                IconButton(onClick = { engine.close(); onClosed() }, modifier = Modifier.testTag("player-close")) { Icon(Icons.Outlined.Close, stringResource(R.string.action_close_player)) }
            }
            if (now == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (state.loading) CircularProgressIndicator() else Text(stringResource(R.string.pl_nothing_playing), style = MaterialTheme.typography.bodyLarge)
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
                        chapter?.let { Text(it.title.ifBlank { stringResource(R.string.pl_chapter_number, chapterIndex + 1) }, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 4.dp)) }
                        CastLine(graph.casting)
                    }
                }
                preferenceError?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error) } }
                item { Timeline(state, chapter.takeIf { settings.useChapterTrack }, settings, onSeek = engine::seekTo) }
                if (settings.useChapterTrack && settings.useTotalTrack && chapter != null) {
                    item { Timeline(state, null, settings, tag = "player-total-slider", onSeek = engine::seekTo) }
                }
                item {
                    when {
                        state.error != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(state.error.orEmpty(), color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center, modifier = Modifier.testTag("player-error"))
                            Button(onClick = engine::retry, modifier = Modifier.testTag("player-retry")) { Text(stringResource(R.string.pl_try_again)) }
                        }
                        state.finished -> Text(stringResource(R.string.finished), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.testTag("player-finished"))
                    }
                }
                item { Controls(state, engine::previousChapter, { engine.jump(false) }, engine::toggle, { engine.jump(true) }, engine::nextChapter, hasChapters = now.chapters.isNotEmpty()) }
                item {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        TextButton(onClick = { speedSheet = true }, modifier = Modifier.testTag("player-speed")) { Text(stringResource(R.string.pl_speed_value, formatSpeed(state.speed))) }
                        val remaining = state.sleepRemaining
                        val sleepTimerLabel = stringResource(R.string.sleep_timer)
                        TextButton(onClick = { tool = "sleep" }, modifier = Modifier.testTag("player-sleep")) {
                            Icon(Icons.Outlined.Bedtime, if (remaining != null) stringResource(R.string.sleep_timer) else null, Modifier.size(18.dp))
                            if (remaining == null) Text(stringResource(R.string.pl_sleep), Modifier.padding(start = 6.dp))
                        }
                        if (remaining != null) Text(formatClock(remaining), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.semantics { stateDescription = sleepTimerLabel }.testTag("sleep-remaining"))
                        if (client != null) TextButton(onClick = { tool = "bookmarks" }, modifier = Modifier.testTag("player-bookmarks")) {
                            Icon(Icons.Outlined.BookmarkBorder, null, Modifier.size(18.dp))
                            Text(stringResource(R.string.bookmarks), Modifier.padding(start = 6.dp))
                        }
                    }
                }
                if (now.chapters.isNotEmpty()) {
                    item { Text(stringResource(R.string.chapters), style = MaterialTheme.typography.titleMedium, modifier = Modifier.fillMaxWidth().semantics { heading() }) }
                    itemsIndexed(now.chapters) { index, item -> ChapterRow(index, item, current = index == chapterIndex, enabled = !settings.lockUi) { engine.seekChapter(index) } }
                }
            }
        }
    }
    when (tool) {
        "sleep" -> SleepSheet(engine, state) { tool = null }
        "bookmarks" -> if (now != null && client != null) BookmarksSheet(client, now.itemId, state.position, engine::seekTo, graph.accounts::handle) { tool = null }
    }
    if (castSheet) CastSheet(graph.casting) { castSheet = false }
    if (speedSheet) {
        ModalBottomSheet(onDismissRequest = { speedSheet = false }) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 8.dp).padding(bottom = 24.dp)) {
                Text(stringResource(R.string.playback_speed), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
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
private fun Timeline(state: PlayerState, chapter: Chapter?, settings: DeviceSettings, tag: String = "player-slider", onSeek: (Double) -> Unit) {
    val now = state.now ?: return
    val start = chapter?.start ?: 0.0
    val end = chapter?.end?.takeIf { it > start } ?: now.duration
    var dragging by remember(start, end, settings.lockUi) { mutableStateOf<Float?>(null) }
    val duration = (end - start).coerceAtLeast(0.001)
    val fraction = dragging ?: ((state.position - start) / duration).toFloat().coerceIn(0f, 1f)
    val shownPosition = start + fraction * duration
    val clockScale = if (settings.scaleElapsedTimeBySpeed) state.speed.toDouble() else 1.0
    val elapsed = formatClock((shownPosition - start).coerceAtLeast(0.0) / clockScale)
    val remaining = formatClock((end - shownPosition).coerceAtLeast(0.0) / clockScale)
    val positionDescription = stringResource(R.string.pl_position_of_duration, elapsed, formatClock(duration / clockScale))
    Column(Modifier.fillMaxWidth()) {
        Slider(
            value = fraction,
            onValueChange = { dragging = it },
            onValueChangeFinished = { dragging?.let { onSeek(start + it * (end - start)) }; dragging = null },
            enabled = !settings.lockUi,
            modifier = Modifier.testTag(tag).semantics { stateDescription = positionDescription },
        )
        Row(Modifier.fillMaxWidth()) {
            Text(elapsed, style = MaterialTheme.typography.labelMedium, modifier = Modifier.testTag(if (tag == "player-slider") "player-position" else "player-total-position"))
            Spacer(Modifier.weight(1f))
            if (state.buffering) Text(stringResource(R.string.pl_buffering), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text("-" + remaining, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Controls(state: PlayerState, onPrevious: () -> Unit, onBack: () -> Unit, onToggle: () -> Unit, onForward: () -> Unit, onNext: () -> Unit, hasChapters: Boolean) {
    val settings by LocalContext.current.graph.settings.settings.collectAsState()
    val haptic = rememberHaptic()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { haptic(); onPrevious() }, enabled = hasChapters && !settings.lockUi, modifier = Modifier.testTag("previous-chapter")) { Icon(Icons.Filled.SkipPrevious, stringResource(R.string.pl_previous_chapter)) }
        IconButton(onClick = { haptic(); onBack() }, enabled = !settings.lockUi, modifier = Modifier.size(56.dp).testTag("jump-back")) { Icon(jumpIcon(false, settings.jumpBackwardsTime), jumpDescription(false, settings.jumpBackwardsTime), Modifier.size(32.dp)) }
        Box(Modifier.testTag(if (state.playing) "player-playing" else "player-paused")) {
            FilledIconButton(onClick = { haptic(); onToggle() }, modifier = Modifier.size(72.dp).testTag("play-pause"), colors = IconButtonDefaults.filledIconButtonColors()) {
                if (state.loading) CircularProgressIndicator(Modifier.size(28.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 3.dp)
                else Icon(if (state.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (state.playing) stringResource(R.string.action_pause) else stringResource(R.string.action_play), Modifier.size(40.dp))
            }
        }
        IconButton(onClick = { haptic(); onForward() }, enabled = !settings.lockUi, modifier = Modifier.size(56.dp).testTag("jump-forward")) { Icon(jumpIcon(true, settings.jumpForwardTime), jumpDescription(true, settings.jumpForwardTime), Modifier.size(32.dp)) }
        IconButton(onClick = { haptic(); onNext() }, enabled = hasChapters && !settings.lockUi, modifier = Modifier.testTag("next-chapter")) { Icon(Icons.Filled.SkipNext, stringResource(R.string.pl_next_chapter)) }
    }
}

private fun jumpIcon(forward: Boolean, seconds: Int): ImageVector = when (seconds) {
    5 -> if (forward) Icons.Filled.Forward5 else Icons.Filled.Replay5
    10 -> if (forward) Icons.Filled.Forward10 else Icons.Filled.Replay10
    30 -> if (forward) Icons.Filled.Forward30 else Icons.Filled.Replay30
    else -> if (forward) Icons.Filled.FastForward else Icons.Filled.FastRewind
}

@Composable
fun jumpDescription(forward: Boolean, seconds: Int): String =
    if (seconds < 60) pluralStringResource(if (forward) R.plurals.pl_jump_forward_seconds else R.plurals.pl_jump_back_seconds, seconds, seconds)
    else (seconds / 60).let { pluralStringResource(if (forward) R.plurals.pl_jump_forward_minutes else R.plurals.pl_jump_back_minutes, it, it) }

@Composable
private fun ChapterRow(index: Int, chapter: Chapter, current: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { selected = current }.padding(vertical = 12.dp).testTag("player-chapter-$index"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(chapter.title.ifBlank { stringResource(R.string.pl_chapter_number, index + 1) }, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f),
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
    val settings by LocalContext.current.graph.settings.settings.collectAsState()
    val jumpBack = settings.jumpBackwardsTime
    if (state.unsavedListening && (state.now == null || state.error == null)) Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.pl_listening_unsaved),
            style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("listening-unsaved"))
    }
    val now = state.now ?: return
    Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth()) {
        Column {
            val chapter = now.chapters.lastOrNull { it.start <= state.position + 0.0005 }
            val (start, end) = chapter?.takeIf { settings.useChapterTrack }?.let { it.start to it.end } ?: (0.0 to now.duration)
            LinearProgressIndicator(progress = { ((state.position - start) / (end - start).coerceAtLeast(0.001)).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(2.dp))
            Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.weight(1f).clickable(role = Role.Button, onClickLabel = stringResource(R.string.pl_open_player), onClick = onOpen).padding(start = 12.dp, top = 8.dp, bottom = 8.dp).testTag("mini-player"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(now.coverUrl, now.title, Modifier.width(44.dp), podcast = now.isPodcast)
                    Column(Modifier.padding(horizontal = 12.dp)) {
                        Text(now.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(state.error?.let { stringResource(R.string.pl_playback_stopped) } ?: chapter?.title?.takeIf { it.isNotBlank() } ?: now.author, style = MaterialTheme.typography.bodySmall,
                            color = if (state.error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                IconButton(onClick = { engine.jump(false) }, enabled = !settings.lockUi, modifier = Modifier.testTag("mini-jump-back")) { Icon(jumpIcon(false, jumpBack), jumpDescription(false, jumpBack)) }
                Box(Modifier.testTag(if (state.playing) "mini-playing" else "mini-paused")) {
                    IconButton(onClick = engine::toggle, modifier = Modifier.testTag("mini-play-pause")) {
                        Icon(if (state.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (state.playing) stringResource(R.string.action_pause) else stringResource(R.string.action_play))
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
                Text(if (loadedHere && state.playing) stringResource(R.string.pl_playing) else if (loadedHere) stringResource(R.string.pl_resume) else stringResource(R.string.action_play), Modifier.padding(start = 6.dp))
            }
        }
        if (refused) Text(stringResource(R.string.pl_streaming_cellular_refused),
            color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("play-cellular-refused"))
        state.openError?.takeIf { it.first == key && !waiting }?.let { (_, message) ->
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("play-error"))
        }
    }
    askCellular?.let { pending ->
        AlertDialog(
            onDismissRequest = { askCellular = null },
            title = { Text(stringResource(R.string.pl_stream_cellular_title)) },
            text = { Text(stringResource(R.string.pl_stream_cellular_message)) },
            confirmButton = { TextButton(onClick = { askCellular = null; start(pending) }, modifier = Modifier.testTag("play-cellular-allow")) { Text(stringResource(R.string.action_stream)) } },
            dismissButton = { TextButton(onClick = { askCellular = null }) { Text(stringResource(R.string.pl_not_now)) } },
        )
    }
}
