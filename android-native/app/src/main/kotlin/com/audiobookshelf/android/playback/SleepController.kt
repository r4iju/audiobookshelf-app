package com.audiobookshelf.android.playback

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.content.ContextCompat
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.core.Chapter
import com.audiobookshelf.core.SleepTimer
import java.util.Calendar
import kotlin.math.sqrt

/** Applies [SleepTimer] to the device: fade volume, chime, shake to reset, and the nightly auto timer. */
class SleepController(private val context: Context, private val settings: SettingsStore, private val onShakeRestart: () -> Unit) {
    data class Outcome(val remaining: Double?, val volume: Float, val expired: Boolean)

    private val timer = SleepTimer()
    private var autoStarted = false
    /** Set when the nightly timer ran out, so the next play can rewind what was slept through. */
    private var autoExpired = false
    private var listening = false
    private var shakeWindowEndsAt = 0L

    val mode get() = timer.mode

    fun start(mode: SleepTimer.Mode, position: Double, chapters: List<Chapter>, speed: Float, auto: Boolean = false) {
        timer.start(mode, position, chapters, speed, SystemClock.elapsedRealtime())
        autoStarted = auto
        autoExpired = false
        listenForShake(true)
    }

    fun cancel() {
        timer.cancel()
        autoStarted = false
        listenForShake(false)
    }

    fun adjust(seconds: Double) = timer.adjust(seconds)

    /** Starts the nightly timer when playback begins inside the configured window. */
    fun maybeStartAuto(position: Double, chapters: List<Chapter>, speed: Float) {
        val current = settings.current
        if (!current.autoSleepTimer || timer.active) return
        val now = Calendar.getInstance()
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        if (SleepTimer.inWindow(minute, minutes(current.autoSleepTimerStartTime), minutes(current.autoSleepTimerEndTime))) {
            start(SleepTimer.Mode.Duration(current.sleepTimerLength / 1000.0), position, chapters, speed, auto = true)
        }
    }

    /** Seconds to rewind on resume after the nightly timer stopped playback, or 0. */
    fun takeAutoRewind(): Double {
        if (!autoExpired) return 0.0
        autoExpired = false
        val current = settings.current
        return if (current.autoSleepTimerAutoRewind) current.autoSleepTimerAutoRewindTime / 1000.0 else 0.0
    }

    fun tick(playing: Boolean, position: Double, speed: Float): Outcome {
        val now = SystemClock.elapsedRealtime()
        val result = timer.tick(now, playing, position, speed)
        if (!timer.active && listening && now > shakeWindowEndsAt) listenForShake(false)
        result ?: return Outcome(null, 1f, false)
        if (result.chime && settings.current.enableSleepTimerAlmostDoneChime) chime()
        if (result.expired) {
            autoExpired = autoStarted
            shakeWindowEndsAt = now + 120_000
        }
        val volume = if (settings.current.disableSleepTimerFadeOut) 1f else result.volume
        return Outcome(if (result.expired) null else result.remaining, volume, result.expired)
    }

    private var lastPosition: () -> Triple<Double, List<Chapter>, Float> = { Triple(0.0, emptyList(), 1f) }

    /** Supplies the playback position used when a shake restarts the timer. */
    fun bind(position: () -> Triple<Double, List<Chapter>, Float>) { lastPosition = position }

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val (x, y, z) = Triple(event.values[0], event.values[1], event.values[2])
            val gForce = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
            if (gForce < settings.current.shakeSensitivity.gravity) return
            val (position, chapters, speed) = lastPosition()
            if (timer.shake(SystemClock.elapsedRealtime(), position, chapters, speed)) {
                listenForShake(true)
                if (!settings.current.disableSleepTimerResetFeedback) vibrate()
                onShakeRestart()
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    private fun listenForShake(enable: Boolean) {
        val sensors = ContextCompat.getSystemService(context, SensorManager::class.java) ?: return
        if (enable && !listening && !settings.current.disableShakeToResetSleepTimer) {
            val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
            listening = sensors.registerListener(sensorListener, accelerometer, SensorManager.SENSOR_DELAY_UI)
        } else if (!enable && listening) {
            sensors.unregisterListener(sensorListener)
            listening = false
        }
    }

    private fun chime() {
        runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, 60).apply { startTone(ToneGenerator.TONE_PROP_BEEP2, 300) } }
    }

    private fun vibrate() {
        val vibrator = ContextCompat.getSystemService(context, Vibrator::class.java) ?: return
        val pattern = longArrayOf(0, 150, 150, 150)
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            else @Suppress("DEPRECATION") vibrator.vibrate(pattern, -1)
        }
    }

    companion object {
        private fun minutes(value: String): Int = value.split(':').let { (it.getOrNull(0)?.toIntOrNull() ?: 0) * 60 + (it.getOrNull(1)?.toIntOrNull() ?: 0) }
    }
}
