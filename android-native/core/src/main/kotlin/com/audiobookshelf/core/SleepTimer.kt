package com.audiobookshelf.core

/**
 * The existing Android app's sleep timer rules: a duration counts down only while playing; end of
 * chapter follows the playback position at the current speed; the last minute fades out with a
 * chime at 30 s; a shake restarts the full length while running or shortly after it ran out.
 */
class SleepTimer {
    sealed interface Mode {
        data class Duration(val seconds: Double) : Mode
        data object EndOfChapter : Mode
    }

    data class Tick(val remaining: Double, val volume: Float, val chime: Boolean, val expired: Boolean)

    var mode: Mode? = null; private set
    /** Book position the end-of-chapter timer stops at. */
    var target: Double? = null; private set
    val active get() = mode != null

    private var remainingDuration = 0.0
    private var startedAt = 0L
    private var lastTick = 0L
    private var wasPlaying = false
    private var chimed = false
    private var expiredAt: Long? = null
    private var lastMode: Mode? = null
    private var lastShake = Long.MIN_VALUE / 2
    private var adjustment = 0.0

    fun start(mode: Mode, position: Double, chapters: List<Chapter>, speed: Float, nowMs: Long) {
        this.mode = mode
        lastMode = mode
        startedAt = nowMs
        lastTick = nowMs
        wasPlaying = false
        chimed = false
        expiredAt = null
        adjustment = 0.0
        when (mode) {
            is Mode.Duration -> { remainingDuration = mode.seconds; target = null }
            Mode.EndOfChapter -> target = chapterEnd(position, chapters)
        }
    }

    fun cancel() {
        mode = null
        target = null
        expiredAt = null
        lastMode = null
    }

    fun adjust(seconds: Double) {
        when (mode) {
            is Mode.Duration -> remainingDuration = (remainingDuration + seconds).coerceAtLeast(0.0)
            Mode.EndOfChapter -> adjustment += seconds
            null -> Unit
        }
    }

    /** Advances the timer; null when no timer is running. */
    fun tick(nowMs: Long, playing: Boolean, position: Double, speed: Float): Tick? {
        val current = mode ?: return null
        if (playing && wasPlaying && current is Mode.Duration) remainingDuration -= (nowMs - lastTick) / 1000.0
        lastTick = nowMs
        wasPlaying = playing
        val remaining = when (current) {
            is Mode.Duration -> remainingDuration
            Mode.EndOfChapter -> ((target ?: position) - position) / speed.coerceAtLeast(0.1f) + adjustment
        }.coerceAtLeast(0.0)
        val chime = !chimed && remaining <= CHIME_AT && remaining > 0
        if (chime) chimed = true
        val expired = remaining <= 0
        if (expired) {
            mode = null
            expiredAt = nowMs
        }
        return Tick(remaining, if (expired) 1f else volumeFor(remaining), chime, expired)
    }

    /** Restarts the full length; returns false when the shake does not apply. */
    fun shake(nowMs: Long, position: Double, chapters: List<Chapter>, speed: Float): Boolean {
        if (nowMs - lastShake < SHAKE_DEBOUNCE_MS) return false
        val running = mode
        val restart = when {
            running != null -> running.takeIf { nowMs - startedAt > SHAKE_GRACE_MS }
            else -> lastMode.takeIf { expiredAt?.let { nowMs - it <= SHAKE_AFTER_EXPIRY_MS } == true }
        } ?: return false
        lastShake = nowMs
        start(restart, position, chapters, speed, nowMs)
        return true
    }

    private fun chapterEnd(position: Double, chapters: List<Chapter>): Double? {
        val index = chapters.indexOfLast { it.start <= position + 0.0005 }.coerceAtLeast(0)
        val chapter = chapters.getOrNull(index) ?: return null
        return if (chapter.end - position < NEXT_CHAPTER_UNDER) chapters.getOrNull(index + 1)?.end ?: chapter.end else chapter.end
    }

    companion object {
        const val FADE_SECONDS = 60.0
        const val CHIME_AT = 30.0
        private const val NEXT_CHAPTER_UNDER = 10.0
        private const val SHAKE_GRACE_MS = 3_000L
        private const val SHAKE_DEBOUNCE_MS = 500L
        private const val SHAKE_AFTER_EXPIRY_MS = 120_000L

        fun volumeFor(remaining: Double): Float =
            if (remaining >= FADE_SECONDS) 1f else (1 - (1 - remaining / FADE_SECONDS) * 0.9).toFloat().coerceIn(0.1f, 1f)

        /** Whether [minuteOfDay] is inside a daily window that may wrap past midnight. */
        fun inWindow(minuteOfDay: Int, start: Int, end: Int): Boolean =
            if (start <= end) minuteOfDay in start until end else minuteOfDay >= start || minuteOfDay < end
    }
}
