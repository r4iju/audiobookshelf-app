package com.audiobookshelf.android.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.Appearance
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.CellularPolicy
import com.audiobookshelf.android.data.DeviceSettings
import com.audiobookshelf.android.data.Diagnostics
import com.audiobookshelf.android.data.Haptics
import com.audiobookshelf.android.data.Orientation
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.data.ShakeSensitivity
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.ListeningStats
import java.text.DateFormat
import java.time.LocalDate
import java.util.Date
import kotlin.math.roundToInt

val JUMP_SECONDS = listOf(5, 10, 15, 30, 60, 120, 300)

/** Performs the tap feedback chosen in settings, or nothing when it is off. */
@Composable
fun rememberHaptic(): () -> Unit {
    val view = LocalView.current
    val graph = LocalContext.current.graph
    return remember(view) {
        {
            when (graph.settings.current.hapticFeedback) {
                Haptics.OFF -> Unit
                Haptics.LIGHT -> view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                Haptics.MEDIUM -> view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                Haptics.HEAVY -> view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            }
        }
    }
}

@Composable
fun SettingsScreen(padding: PaddingValues, onDiagnostics: () -> Unit) {
    val graph = LocalContext.current.graph
    val settings by graph.settings.settings.collectAsState()
    var error by remember { mutableStateOf<String?>(null) }
    val change: ((DeviceSettings) -> DeviceSettings) -> Unit = { transform ->
        error = try { graph.settings.update(transform); null } catch (_: java.io.IOException) {
            "Settings could not be saved on this device, so nothing changed. Free some storage and try again."
        }
    }
    LazyColumn(
        Modifier.fillMaxSize().padding(padding).testTag("settings"),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        error?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("settings-error")) } }
        item { SettingsHeading("Appearance") }
        item {
            Choices("Theme", Appearance.entries, settings.appearance, "theme", label = { it.name.lowercase().replaceFirstChar(Char::titlecase) }) { value -> change { it.copy(appearance = value) } }
        }
        item {
            Choices("Screen orientation", Orientation.entries, settings.lockOrientation, "orientation", label = {
                when (it) { Orientation.NONE -> "Follow device"; Orientation.PORTRAIT -> "Portrait"; Orientation.LANDSCAPE -> "Landscape" }
            }) { value -> change { it.copy(lockOrientation = value) } }
        }
        item {
            Choices("Haptic feedback", Haptics.entries, settings.hapticFeedback, "haptic", label = { it.name.lowercase().replaceFirstChar(Char::titlecase) }) { value -> change { it.copy(hapticFeedback = value) } }
        }

        item { SettingsHeading("Playback") }
        item { Choices("Jump forward", JUMP_SECONDS, settings.jumpForwardTime, "jump-forward", label = ::jumpLabel) { value -> change { it.copy(jumpForwardTime = value) } } }
        item { Choices("Jump back", JUMP_SECONDS, settings.jumpBackwardsTime, "jump-back", label = ::jumpLabel) { value -> change { it.copy(jumpBackwardsTime = value) } } }
        item {
            Toggle("Rewind a little when resuming", "Steps back a few seconds after a pause, more after a longer one.", !settings.disableAutoRewind, "auto-rewind") { on -> change { it.copy(disableAutoRewind = !on) } }
        }
        item {
            Toggle("Seek from system controls", "Lets the lock screen and notification move the position bar.", settings.allowSeekingOnMediaControls, "seek-media-controls") { on -> change { it.copy(allowSeekingOnMediaControls = on) } }
        }
        item {
            Toggle("Accurate MP3 seeking", "Builds a seek index for MP3 files with unreliable lengths. Seeking starts more slowly.", settings.enableMp3IndexSeeking, "mp3-index-seeking") { on -> change { it.copy(enableMp3IndexSeeking = on) } }
        }

        item { SettingsHeading("Sleep timer") }
        item {
            Toggle("Shake to reset", "Shaking the phone while the timer runs restarts it.", !settings.disableShakeToResetSleepTimer, "sleep-shake") { on -> change { it.copy(disableShakeToResetSleepTimer = !on) } }
        }
        if (!settings.disableShakeToResetSleepTimer) item {
            Choices("Shake sensitivity", ShakeSensitivity.entries, settings.shakeSensitivity, "shake", label = { it.name.lowercase().replace('_', ' ').replaceFirstChar(Char::titlecase) }) { value -> change { it.copy(shakeSensitivity = value) } }
        }
        item { Toggle("Fade out", "Lowers the volume during the last minute.", !settings.disableSleepTimerFadeOut, "sleep-fade") { on -> change { it.copy(disableSleepTimerFadeOut = !on) } } }
        item { Toggle("Vibrate on reset", null, !settings.disableSleepTimerResetFeedback, "sleep-reset-feedback") { on -> change { it.copy(disableSleepTimerResetFeedback = !on) } } }
        item { Toggle("Chime when almost done", null, settings.enableSleepTimerAlmostDoneChime, "sleep-chime") { on -> change { it.copy(enableSleepTimerAlmostDoneChime = on) } } }
        item {
            Toggle("Automatic sleep timer", "Starts the timer when playing between ${settings.autoSleepTimerStartTime} and ${settings.autoSleepTimerEndTime}.", settings.autoSleepTimer, "auto-sleep") { on -> change { it.copy(autoSleepTimer = on) } }
        }
        if (settings.autoSleepTimer) {
            item { Choices("Starts at", AUTO_SLEEP_HOURS, settings.autoSleepTimerStartTime, "auto-sleep-start", label = { it }) { value -> change { it.copy(autoSleepTimerStartTime = value) } } }
            item { Choices("Ends at", AUTO_SLEEP_HOURS, settings.autoSleepTimerEndTime, "auto-sleep-end", label = { it }) { value -> change { it.copy(autoSleepTimerEndTime = value) } } }
        }

        item { SettingsHeading("Mobile data") }
        item { Choices("Downloads on mobile data", CellularPolicy.entries, settings.downloadUsingCellular, "download-cellular", label = ::policyLabel) { value -> change { it.copy(downloadUsingCellular = value) } } }
        item { Choices("Streaming on mobile data", CellularPolicy.entries, settings.streamingUsingCellular, "stream-cellular", label = ::policyLabel) { value -> change { it.copy(streamingUsingCellular = value) } } }

        item { SettingsHeading("Support") }
        item {
            OutlinedButton(onClick = onDiagnostics, modifier = Modifier.fillMaxWidth().testTag("open-diagnostics")) { Text("Diagnostics") }
        }
    }
}

private val AUTO_SLEEP_HOURS = listOf("20:00", "21:00", "22:00", "23:00", "00:00", "05:00", "06:00", "07:00", "08:00")

private fun jumpLabel(seconds: Int) = if (seconds < 60) "${seconds}s" else "${seconds / 60}m"

private fun policyLabel(policy: CellularPolicy) = when (policy) { CellularPolicy.ASK -> "Ask"; CellularPolicy.ALWAYS -> "Always"; CellularPolicy.NEVER -> "Never" }

@Composable
private fun SettingsHeading(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 12.dp).semantics { heading() })
}

@Composable
private fun <T> Choices(title: String, values: List<T>, current: T, tagPrefix: String, label: (T) -> String, onChoose: (T) -> Unit) {
    val haptic = rememberHaptic()
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            values.forEach { value ->
                val chosen = value == current
                val tag = "$tagPrefix-" + (if (value is Enum<*>) value.name.lowercase().replace('_', '-') else value.toString())
                FilterChip(
                    selected = chosen,
                    onClick = { haptic(); onChoose(value) },
                    label = { Text(label(value)) },
                    modifier = Modifier.testTag(tag).semantics { selected = chosen },
                )
            }
        }
    }
}

@Composable
private fun Toggle(title: String, detail: String?, on: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Switch(checked = on, onCheckedChange = onChange, modifier = Modifier.testTag(tag).semantics { contentDescription = title })
    }
}

@Composable
fun StatisticsScreen(active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues) {
    val graph = LocalContext.current.graph
    var stats by remember { mutableStateOf<ListeningStats?>(null) }
    var finished by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        error = null
        try {
            stats = active.client.listeningStats()
            finished = catalog.freshUser().mediaProgress.count { it.isFinished }
        } catch (failure: Exception) {
            graph.diagnostics.record(Diagnostics.Area.CONNECTION, "Listening statistics could not be loaded", failure)
            graph.accounts.handle(failure)
            error = failure.message ?: "Something went wrong."
        }
    }
    val current = stats
    Box(Modifier.fillMaxSize().padding(padding)) {
        when {
            error != null && current == null -> MessageState("Statistics not available", error, tag = "statistics-error", action = "Try again", onAction = { attempt++ })
            current == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            else -> LazyColumn(Modifier.fillMaxSize().testTag("statistics"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("${minutes(current.totalTime)} minutes listened", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                        Text("${current.days.size} days listened")
                        Text("$finished ${if (finished == 1) "title" else "titles"} finished")
                    }
                }
                item { WeekChart(current) }
                if (current.recentSessions.isNotEmpty()) item { SettingsHeading("Recent sessions") }
                itemsIndexed(current.recentSessions) { index, session ->
                    Column(Modifier.testTag("stats-session-$index")) {
                        Text(session.title, style = MaterialTheme.typography.bodyLarge)
                        Text(listOfNotNull(session.author.takeIf { it.isNotEmpty() }, "${minutes(session.timeListening)} minutes listened").joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun minutes(seconds: Double) = (seconds / 60).roundToInt()

/** Minutes listened on each of the last seven days, keyed like the server's `days` map. */
@Composable
private fun WeekChart(stats: ListeningStats) {
    val today = LocalDate.now()
    val days = (6 downTo 0).map { today.minusDays(it.toLong()) }.map { it to (stats.days[it.toString()] ?: 0.0) }
    val most = days.maxOf { it.second }.coerceAtLeast(60.0)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Minutes listened in the last 7 days", style = MaterialTheme.typography.titleSmall)
        Row(Modifier.fillMaxWidth().height(120.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            days.forEach { (date, time) ->
                val name = date.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault())
                Column(
                    Modifier.weight(1f).fillMaxHeight().clearAndSetSemantics { contentDescription = "$name, ${minutes(time)} minutes listened" },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom,
                ) {
                    Box(Modifier.width(18.dp).fillMaxHeight((time / most).toFloat().coerceIn(0.02f, 0.85f))
                        .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp)))
                    Text(name, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
fun DiagnosticsScreen(active: SessionState.Active, padding: PaddingValues) {
    val graph = LocalContext.current.graph
    val entries by graph.diagnostics.entries.collectAsState()
    val time = remember { DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.MEDIUM) }
    LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("diagnostics"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("diagnostic-connection"), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Connection", style = MaterialTheme.typography.titleSmall)
                Text("Server ${active.client.account.server.substringAfter("://")}")
                Text("Signed in as ${active.connection.credentials.username}")
                Text("App ${com.audiobookshelf.android.BuildConfig.VERSION_NAME}")
            }
        }
        item {
            Row(verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f)) { SettingsHeading("Recent problems") }
                if (entries.isNotEmpty()) TextButton(onClick = { graph.diagnostics.clear() }, modifier = Modifier.testTag("diagnostics-clear")) { Text("Clear") }
            }
        }
        if (entries.isEmpty()) item { Text("No problems recorded on this device.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("diagnostics-empty")) }
        itemsIndexed(entries) { index, entry ->
            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("diagnostic-$index")) {
                Text("${entry.area.name.lowercase().replaceFirstChar(Char::titlecase)} · ${time.format(Date(entry.at))}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(entry.message, style = MaterialTheme.typography.bodyMedium)
            }
            HorizontalDivider(Modifier.padding(top = 8.dp))
        }
    }
}
