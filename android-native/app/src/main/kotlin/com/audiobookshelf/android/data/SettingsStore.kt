package com.audiobookshelf.android.data

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File

enum class Appearance { SYSTEM, LIGHT, DARK, BLACK }
enum class Haptics { OFF, LIGHT, MEDIUM, HEAVY }
enum class Orientation { NONE, PORTRAIT, LANDSCAPE }
enum class ShakeSensitivity(val gravity: Float) { VERY_LOW(2.7f), LOW(2f), MEDIUM(1.5f), HIGH(1.3f), VERY_HIGH(1.1f) }
enum class CellularPolicy { ASK, ALWAYS, NEVER }
enum class SeriesOrder { ASC, DESC }

/**
 * Device preferences. Field names and defaults follow the legacy Android `DeviceSettings` so a
 * migrated installation keeps its behavior; display-only fields are new to the native client.
 */
@Serializable data class DeviceSettings(
    val disableAutoRewind: Boolean = false,
    val enableAltView: Boolean = true,
    val allowSeekingOnMediaControls: Boolean = false,
    val jumpBackwardsTime: Int = 10,
    val jumpForwardTime: Int = 10,
    val enableMp3IndexSeeking: Boolean = false,
    val disableShakeToResetSleepTimer: Boolean = false,
    val shakeSensitivity: ShakeSensitivity = ShakeSensitivity.MEDIUM,
    val lockOrientation: Orientation = Orientation.NONE,
    val hapticFeedback: Haptics = Haptics.LIGHT,
    val autoSleepTimer: Boolean = false,
    val autoSleepTimerStartTime: String = "22:00",
    val autoSleepTimerEndTime: String = "06:00",
    val autoSleepTimerAutoRewind: Boolean = false,
    val autoSleepTimerAutoRewindTime: Long = 300_000,
    val sleepTimerLength: Long = 900_000,
    val disableSleepTimerFadeOut: Boolean = false,
    val disableSleepTimerResetFeedback: Boolean = false,
    val enableSleepTimerAlmostDoneChime: Boolean = false,
    val languageCode: String = "en-us",
    val downloadUsingCellular: CellularPolicy = CellularPolicy.ALWAYS,
    val streamingUsingCellular: CellularPolicy = CellularPolicy.ALWAYS,
    val androidAutoBrowseLimitForGrouping: Int = 100,
    val androidAutoBrowseSeriesSequenceOrder: SeriesOrder = SeriesOrder.ASC,
    val playbackRate: Float = 1f,
    val appearance: Appearance = Appearance.SYSTEM,
    val listLayout: Boolean = false,
    val catalogSort: String = "media.metadata.title",
    val catalogDescending: Boolean = false,
    val episodeSort: String = "publishedAt",
    val episodeDescending: Boolean = true,
    /** Browse media ID of the last opened title, for resuming from Bluetooth or the system media controls. */
    val lastPlayed: String? = null,
    /** PDF pages scroll as one continuous column instead of one page at a time. */
    val pdfContinuous: Boolean = false,
    /** Folder tree new downloads are saved in, chosen through the system picker; app storage when null. */
    val downloadFolder: String? = null,
    val downloadFolderName: String? = null,
)

class SettingsStore(private val file: File) {
    private val state = MutableStateFlow(read())
    val settings: StateFlow<DeviceSettings> = state
    val current get() = state.value

    @Synchronized
    fun update(transform: (DeviceSettings) -> DeviceSettings) {
        val next = transform(state.value)
        writeAtomically(file, AbsJson.encodeToString(DeviceSettings.serializer(), next).toByteArray())
        state.value = next
    }

    private fun read(): DeviceSettings = if (file.exists()) {
        runCatching { AbsJson.decodeFromString(DeviceSettings.serializer(), file.readText()) }.getOrElse { DeviceSettings() }
    } else DeviceSettings()
}
