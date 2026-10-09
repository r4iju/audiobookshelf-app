package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import android.content.Context
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
import com.audiobookshelf.android.data.SeriesOrder
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
    val context = LocalContext.current
    val graph = context.graph
    val settings by graph.settings.settings.collectAsState()
    var error by remember { mutableStateOf<String?>(null) }
    val saveFailed = stringResource(R.string.set_settings_not_saved)
    val orientations = mapOf(Orientation.NONE to stringResource(R.string.set_orientation_follow_device), Orientation.PORTRAIT to stringResource(R.string.set_orientation_portrait), Orientation.LANDSCAPE to stringResource(R.string.set_orientation_landscape))
    val haptics = mapOf(Haptics.OFF to stringResource(R.string.set_haptic_off), Haptics.LIGHT to stringResource(R.string.set_haptic_light), Haptics.MEDIUM to stringResource(R.string.level_medium), Haptics.HEAVY to stringResource(R.string.set_haptic_heavy))
    val seriesOrders = mapOf(SeriesOrder.ASC to stringResource(R.string.set_series_first_to_last), SeriesOrder.DESC to stringResource(R.string.set_series_last_to_first))
    val themes = mapOf(Appearance.SYSTEM to stringResource(R.string.theme_system), Appearance.LIGHT to stringResource(R.string.theme_light), Appearance.DARK to stringResource(R.string.theme_dark), Appearance.BLACK to stringResource(R.string.theme_black))
    val levels = mapOf(ShakeSensitivity.VERY_LOW to stringResource(R.string.level_very_low), ShakeSensitivity.LOW to stringResource(R.string.level_low), ShakeSensitivity.MEDIUM to stringResource(R.string.level_medium), ShakeSensitivity.HIGH to stringResource(R.string.level_high), ShakeSensitivity.VERY_HIGH to stringResource(R.string.level_very_high))
    val policies = mapOf(CellularPolicy.ASK to stringResource(R.string.policy_ask), CellularPolicy.ALWAYS to stringResource(R.string.policy_always), CellularPolicy.NEVER to stringResource(R.string.policy_never))
    val change: ((DeviceSettings) -> DeviceSettings) -> Unit = { transform ->
        error = try { graph.settings.update(transform); null } catch (_: java.io.IOException) {
            saveFailed
        }
    }
    LazyColumn(
        Modifier.fillMaxSize().padding(padding).testTag("settings"),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        error?.let { message -> item { Text(message, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("settings-error")) } }
        item { SettingsHeading(stringResource(R.string.settings_appearance)) }
        item {
            Choices(stringResource(R.string.theme), Appearance.entries, settings.appearance, "theme", label = { themes.getValue(it) }) { value -> change { it.copy(appearance = value) } }
        }
        item {
            Choices(stringResource(R.string.screen_orientation), Orientation.entries, settings.lockOrientation, "orientation", label = { orientations.getValue(it) }) { value -> change { it.copy(lockOrientation = value) } }
        }
        item {
            Choices(stringResource(R.string.haptic_feedback), Haptics.entries, settings.hapticFeedback, "haptic", label = { haptics.getValue(it) }) { value -> change { it.copy(hapticFeedback = value) } }
        }

        item { SettingsHeading(stringResource(R.string.settings_playback)) }
        item { Toggle(stringResource(R.string.pl_chapter_track), null, settings.useChapterTrack, "chapter-track") { on -> change { it.copy(useChapterTrack = on, useTotalTrack = it.useTotalTrack || !on) } } }
        item { Toggle(stringResource(R.string.pl_total_track), null, settings.useTotalTrack, "total-track") { on -> change { it.copy(useTotalTrack = on, useChapterTrack = it.useChapterTrack || !on) } } }
        item { Toggle(stringResource(R.string.pl_scale_elapsed), null, settings.scaleElapsedTimeBySpeed, "scale-elapsed") { on -> change { it.copy(scaleElapsedTimeBySpeed = on) } } }
        item { Toggle(stringResource(R.string.pl_lock), null, settings.lockUi, "lock-player") { on -> change { it.copy(lockUi = on) } } }
        item { Choices(stringResource(R.string.jump_forward_time), JUMP_SECONDS, settings.jumpForwardTime, "jump-forward", label = { jumpLabel(context, it) }) { value -> change { it.copy(jumpForwardTime = value) } } }
        item { Choices(stringResource(R.string.jump_back_time), JUMP_SECONDS, settings.jumpBackwardsTime, "jump-back", label = { jumpLabel(context, it) }) { value -> change { it.copy(jumpBackwardsTime = value) } } }
        item {
            Toggle(stringResource(R.string.set_rewind_on_resume), stringResource(R.string.set_rewind_on_resume_detail), !settings.disableAutoRewind, "auto-rewind") { on -> change { it.copy(disableAutoRewind = !on) } }
        }
        item {
            Toggle(stringResource(R.string.set_seek_system_controls), stringResource(R.string.set_seek_system_controls_detail), settings.allowSeekingOnMediaControls, "seek-media-controls") { on -> change { it.copy(allowSeekingOnMediaControls = on) } }
        }
        item {
            Toggle(stringResource(R.string.set_mp3_index_seeking), stringResource(R.string.set_mp3_index_seeking_detail), settings.enableMp3IndexSeeking, "mp3-index-seeking") { on -> change { it.copy(enableMp3IndexSeeking = on) } }
        }

        item { SettingsHeading(stringResource(R.string.settings_sleep_timer)) }
        item {
            Toggle(stringResource(R.string.set_shake_to_reset), stringResource(R.string.set_shake_to_reset_detail), !settings.disableShakeToResetSleepTimer, "sleep-shake") { on -> change { it.copy(disableShakeToResetSleepTimer = !on) } }
        }
        if (!settings.disableShakeToResetSleepTimer) item {
            Choices(stringResource(R.string.shake_sensitivity), ShakeSensitivity.entries, settings.shakeSensitivity, "shake", label = { levels.getValue(it) }) { value -> change { it.copy(shakeSensitivity = value) } }
        }
        item { Toggle(stringResource(R.string.set_sleep_fade_out), stringResource(R.string.set_sleep_fade_out_detail), !settings.disableSleepTimerFadeOut, "sleep-fade") { on -> change { it.copy(disableSleepTimerFadeOut = !on) } } }
        item { Toggle(stringResource(R.string.set_vibrate_on_reset), null, !settings.disableSleepTimerResetFeedback, "sleep-reset-feedback") { on -> change { it.copy(disableSleepTimerResetFeedback = !on) } } }
        item { Toggle(stringResource(R.string.set_sleep_chime), null, settings.enableSleepTimerAlmostDoneChime, "sleep-chime") { on -> change { it.copy(enableSleepTimerAlmostDoneChime = on) } } }
        item {
            Toggle(stringResource(R.string.auto_sleep_timer), stringResource(R.string.set_auto_sleep_timer_detail, settings.autoSleepTimerStartTime, settings.autoSleepTimerEndTime), settings.autoSleepTimer, "auto-sleep") { on -> change { it.copy(autoSleepTimer = on) } }
        }
        if (settings.autoSleepTimer) {
            item { Choices(stringResource(R.string.set_auto_sleep_starts_at), AUTO_SLEEP_HOURS, settings.autoSleepTimerStartTime, "auto-sleep-start", label = { it }) { value -> change { it.copy(autoSleepTimerStartTime = value) } } }
            item { Choices(stringResource(R.string.set_auto_sleep_ends_at), AUTO_SLEEP_HOURS, settings.autoSleepTimerEndTime, "auto-sleep-end", label = { it }) { value -> change { it.copy(autoSleepTimerEndTime = value) } } }
        }

        item { SettingsHeading(stringResource(R.string.set_heading_mobile_data)) }
        item { Choices(stringResource(R.string.downloads_on_mobile_data), CellularPolicy.entries, settings.downloadUsingCellular, "download-cellular", label = { policies.getValue(it) }) { value -> change { it.copy(downloadUsingCellular = value) } } }
        item { Choices(stringResource(R.string.streaming_on_mobile_data), CellularPolicy.entries, settings.streamingUsingCellular, "stream-cellular", label = { policies.getValue(it) }) { value -> change { it.copy(streamingUsingCellular = value) } } }

        item { SettingsHeading(stringResource(R.string.set_storage)) }
        item { DownloadLocation(settings, change) }

        item { ImportLegacyButton() }
        item { SettingsHeading(stringResource(R.string.settings_android_auto)) }
        item {
            Choices(stringResource(R.string.set_car_grouping), (CAR_GROUPING + settings.androidAutoBrowseLimitForGrouping).distinct().sorted(), settings.androidAutoBrowseLimitForGrouping, "car-grouping", label = { it.toString() }) { value -> change { it.copy(androidAutoBrowseLimitForGrouping = value) } }
        }
        item {
            Choices(stringResource(R.string.series_books_order), SeriesOrder.entries, settings.androidAutoBrowseSeriesSequenceOrder, "car-series-order", label = { seriesOrders.getValue(it) }) { value -> change { it.copy(androidAutoBrowseSeriesSequenceOrder = value) } }
        }

        item { SettingsHeading(stringResource(R.string.set_heading_support)) }
        item { LeafwakeLegal() }
        item {
            OutlinedButton(onClick = onDiagnostics, modifier = Modifier.fillMaxWidth().testTag("open-diagnostics")) { Text(stringResource(R.string.set_diagnostics)) }
        }
    }
}

private val CAR_GROUPING = listOf(25, 50, 100, 200, 500)

private val AUTO_SLEEP_HOURS = listOf("20:00", "21:00", "22:00", "23:00", "00:00", "05:00", "06:00", "07:00", "08:00")

private fun jumpLabel(context: Context, seconds: Int) =
    if (seconds < 60) context.getString(R.string.set_unit_seconds_short, seconds) else context.getString(R.string.set_unit_minutes_short, seconds / 60)

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
    val somethingWrong = stringResource(R.string.set_something_went_wrong)
    LaunchedEffect(attempt) {
        error = null
        try {
            stats = active.client.listeningStats()
            finished = catalog.freshUser().mediaProgress.count { it.isFinished }
        } catch (failure: Exception) {
            graph.diagnostics.record(Diagnostics.Area.CONNECTION, "Listening statistics could not be loaded", failure)
            graph.accounts.handle(failure)
            error = failure.localizedMessage ?: somethingWrong
        }
    }
    val current = stats
    Box(Modifier.fillMaxSize().padding(padding)) {
        when {
            error != null && current == null -> MessageState(stringResource(R.string.set_statistics_unavailable), error, tag = "statistics-error", action = stringResource(R.string.set_try_again), onAction = { attempt++ })
            current == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            else -> LazyColumn(Modifier.fillMaxSize().testTag("statistics"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(pluralStringResource(R.plurals.set_minutes_listened, minutes(current.totalTime), minutes(current.totalTime)), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                        Text(pluralStringResource(R.plurals.set_days_listened, current.days.size, current.days.size))
                        Text(pluralStringResource(R.plurals.set_titles_finished, finished, finished))
                    }
                }
                item { WeekChart(current) }
                if (current.recentSessions.isNotEmpty()) item { SettingsHeading(stringResource(R.string.set_recent_sessions)) }
                itemsIndexed(current.recentSessions) { index, session ->
                    val listened = pluralStringResource(R.plurals.set_minutes_listened, minutes(session.timeListening), minutes(session.timeListening))
                    Column(Modifier.testTag("stats-session-$index")) {
                        Text(session.title, style = MaterialTheme.typography.bodyLarge)
                        Text(listOfNotNull(session.author.takeIf { it.isNotEmpty() }, listened).joinToString(" · "),
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
        Text(stringResource(R.string.set_week_chart_title), style = MaterialTheme.typography.titleSmall)
        Row(Modifier.fillMaxWidth().height(120.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            days.forEach { (date, time) ->
                val name = date.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault())
                val description = pluralStringResource(R.plurals.set_day_minutes_listened, minutes(time), name, minutes(time))
                Column(
                    Modifier.weight(1f).fillMaxHeight().clearAndSetSemantics { contentDescription = description },
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
    val unreadableResets by graph.resets.unreadable.collectAsState()
    var resolving by remember { mutableStateOf(false) }
    var resolveError by remember { mutableStateOf<String?>(null) }
    val unreadableWrites by graph.publications.unreadable.collectAsState()
    val unsavedRecovery by graph.listeningRecovery.problem.collectAsState()
    var settingAside by remember { mutableStateOf(false) }
    val setAsideFailed = stringResource(R.string.set_set_aside_failed)
    val areaLabels = mapOf(Diagnostics.Area.CONNECTION to stringResource(R.string.set_connection), Diagnostics.Area.MEDIA to stringResource(R.string.set_diagnostics_area_media),
        Diagnostics.Area.SYNC to stringResource(R.string.set_diagnostics_area_sync), Diagnostics.Area.STORAGE to stringResource(R.string.set_storage))
    LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("diagnostics"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (unreadableResets) item {
            Column(Modifier.testTag("unreadable-resets"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.set_unreadable_resets_title), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                Text(stringResource(R.string.set_unreadable_resets_detail),
                    style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { resolving = true }, modifier = Modifier.testTag("resolve-unreadable-resets")) { Text(stringResource(R.string.set_set_them_aside)) }
                resolveError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }
        if (unsavedRecovery != null) item {
            Column(Modifier.testTag("listening-storage"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.set_listening_storage_title), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                Text(stringResource(R.string.set_listening_storage_detail),
                    style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { if (graph.listeningRecovery.run()) graph.progressSync.publishAll() }, modifier = Modifier.testTag("retry-listening-storage")) { Text(stringResource(R.string.set_try_again)) }
            }
        }
        if (unreadableWrites) item {
            Column(Modifier.testTag("unreadable-writes"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.set_unreadable_writes_title), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error)
                Text(stringResource(R.string.set_unreadable_writes_detail),
                    style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { settingAside = true }, modifier = Modifier.testTag("resolve-unreadable-writes")) { Text(stringResource(R.string.set_set_them_aside)) }
            }
        }
        item {
            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("diagnostic-connection"), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.set_connection), style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.set_diagnostics_server, active.client.account.server.substringAfter("://")))
                Text(stringResource(R.string.set_diagnostics_signed_in_as, active.connection.credentials.username))
                Text(stringResource(R.string.set_diagnostics_app_version, com.audiobookshelf.android.BuildConfig.VERSION_NAME))
            }
        }
        item {
            Row(verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f)) { SettingsHeading(stringResource(R.string.set_recent_problems)) }
                if (entries.isNotEmpty()) TextButton(onClick = { graph.diagnostics.clear() }, modifier = Modifier.testTag("diagnostics-clear")) { Text(stringResource(R.string.set_clear)) }
            }
        }
        if (entries.isEmpty()) item { Text(stringResource(R.string.set_no_problems), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("diagnostics-empty")) }
        itemsIndexed(entries) { index, entry ->
            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("diagnostic-$index")) {
                Text("${areaLabels.getValue(entry.area)} · ${time.format(Date(entry.at))}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(entry.message, style = MaterialTheme.typography.bodyMedium)
            }
            HorizontalDivider(Modifier.padding(top = 8.dp))
        }
    }
    if (settingAside) androidx.compose.material3.AlertDialog(
        onDismissRequest = { settingAside = false },
        title = { Text(stringResource(R.string.set_unreadable_writes_confirm_title)) },
        text = { Text(stringResource(R.string.set_unreadable_writes_confirm_detail)) },
        confirmButton = {
            TextButton(onClick = {
                settingAside = false
                runCatching { graph.publications.setAsideUnreadable(); graph.progressSync.publishAll(); graph.readingSync.publishAll(); graph.completeResets() }
                    .onFailure { resolveError = it.localizedMessage ?: setAsideFailed }
            }, modifier = Modifier.testTag("confirm-resolve-unreadable-writes")) { Text(stringResource(R.string.set_set_aside)) }
        },
        dismissButton = { TextButton(onClick = { settingAside = false }) { Text(stringResource(R.string.action_cancel)) } },
    )
    if (resolving) androidx.compose.material3.AlertDialog(
        onDismissRequest = { resolving = false },
        title = { Text(stringResource(R.string.set_unreadable_resets_confirm_title)) },
        text = { Text(stringResource(R.string.set_unreadable_resets_confirm_detail)) },
        confirmButton = {
            TextButton(onClick = {
                resolving = false
                runCatching { graph.resets.abandonUnreadable(); graph.readingSync.publishAll() }
                    .onFailure { resolveError = it.localizedMessage ?: setAsideFailed }
            }, modifier = Modifier.testTag("confirm-resolve-unreadable-resets")) { Text(stringResource(R.string.set_set_aside)) }
        },
        dismissButton = { TextButton(onClick = { resolving = false }) { Text(stringResource(R.string.action_cancel)) } },
    )
}
