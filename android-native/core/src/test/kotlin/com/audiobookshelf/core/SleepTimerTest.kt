package com.audiobookshelf.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepTimerTest {
    private val chapters = listOf(Chapter(0, 0.0, 30.0, "One"), Chapter(1, 30.0, 400.0, "Two"), Chapter(2, 400.0, 900.0, "Three"))

    @Test
    fun durationTimerCountsOnlyWhilePlayingAndExpiresOnce() {
        val timer = SleepTimer()
        timer.start(SleepTimer.Mode.Duration(120.0), position = 0.0, chapters = chapters, speed = 1f, nowMs = 0)
        assertEquals(120.0, timer.tick(nowMs = 10_000, playing = true, position = 10.0, speed = 1f)!!.remaining, 0.001)
        assertEquals(110.0, timer.tick(nowMs = 20_000, playing = true, position = 20.0, speed = 1f)!!.remaining, 0.001)
        // Paused time does not count.
        assertEquals(110.0, timer.tick(nowMs = 80_000, playing = false, position = 20.0, speed = 1f)!!.remaining, 0.001)
        assertEquals(110.0, timer.tick(nowMs = 90_000, playing = true, position = 20.0, speed = 1f)!!.remaining, 0.001)
        val last = timer.tick(nowMs = 200_000, playing = true, position = 130.0, speed = 1f)!!
        assertTrue(last.expired)
        assertNull(timer.tick(nowMs = 191_000, playing = true, position = 131.0, speed = 1f))
    }

    @Test
    fun endOfChapterUsesTheNextChapterWhenTheCurrentOneIsAlmostOverAndScalesBySpeed() {
        val timer = SleepTimer()
        timer.start(SleepTimer.Mode.EndOfChapter, position = 25.0, chapters = chapters, speed = 1f, nowMs = 0)
        assertEquals(400.0, timer.target)
        assertEquals(375.0, timer.tick(nowMs = 0, playing = true, position = 25.0, speed = 1f)!!.remaining, 0.001)
        assertEquals(150.0, timer.tick(nowMs = 100, playing = true, position = 100.0, speed = 2f)!!.remaining, 0.001)
        assertTrue(timer.tick(nowMs = 200, playing = true, position = 400.0, speed = 2f)!!.expired)

        val normal = SleepTimer()
        normal.start(SleepTimer.Mode.EndOfChapter, position = 10.0, chapters = chapters, speed = 1f, nowMs = 0)
        assertEquals(30.0, normal.target)
    }

    @Test
    fun fadesOverTheLastMinuteAndChimesOnceAtThirtySeconds() {
        val timer = SleepTimer()
        timer.start(SleepTimer.Mode.Duration(90.0), position = 0.0, chapters = chapters, speed = 1f, nowMs = 0)
        timer.tick(0, true, 0.0, 1f)
        val early = timer.tick(20_000, true, 20.0, 1f)!!
        assertEquals(1f, early.volume, 0.0001f)
        assertFalse(early.chime)
        val fading = timer.tick(60_000, true, 60.0, 1f)!!
        assertEquals(30.0, fading.remaining, 0.001)
        assertEquals(0.55f, fading.volume, 0.0001f)
        assertTrue(fading.chime)
        assertFalse(timer.tick(61_000, true, 61.0, 1f)!!.chime)
    }

    @Test
    fun shakeRestartsTheFullLengthWhileRunningAndShortlyAfterExpiry() {
        val timer = SleepTimer()
        timer.start(SleepTimer.Mode.Duration(60.0), position = 0.0, chapters = chapters, speed = 1f, nowMs = 0)
        timer.tick(0, true, 0.0, 1f)
        assertFalse("Too soon after starting", timer.shake(nowMs = 2_000, position = 2.0, chapters = chapters, speed = 1f))
        timer.tick(40_000, true, 40.0, 1f)
        assertTrue(timer.shake(nowMs = 40_000, position = 40.0, chapters = chapters, speed = 1f))
        assertFalse("Debounced", timer.shake(nowMs = 40_200, position = 40.0, chapters = chapters, speed = 1f))
        assertEquals(60.0, timer.tick(40_300, true, 40.3, 1f)!!.remaining, 0.5)

        assertTrue(timer.tick(101_000, true, 101.0, 1f)!!.expired)
        assertTrue("Within two minutes of expiry", timer.shake(nowMs = 200_000, position = 101.0, chapters = chapters, speed = 1f))
        assertTrue(timer.active)
        timer.cancel()
        assertFalse(timer.shake(nowMs = 201_000, position = 101.0, chapters = chapters, speed = 1f))

        val late = SleepTimer()
        late.start(SleepTimer.Mode.Duration(10.0), 0.0, chapters, 1f, 0)
        late.tick(0, true, 0.0, 1f)
        assertTrue(late.tick(10_000, true, 10.0, 1f)!!.expired)
        assertFalse(late.shake(nowMs = 131_000, position = 10.0, chapters = chapters, speed = 1f))
    }

    @Test
    fun adjustingChangesTheRemainingTimeButNeverBelowZero() {
        val timer = SleepTimer()
        timer.start(SleepTimer.Mode.Duration(600.0), 0.0, chapters, 1f, 0)
        timer.adjust(300.0)
        assertEquals(900.0, timer.tick(0, true, 0.0, 1f)!!.remaining, 0.001)
        timer.adjust(-1200.0)
        assertTrue(timer.tick(0, true, 0.0, 1f)!!.expired)
    }

    @Test
    fun autoSleepWindowWrapsPastMidnight() {
        assertTrue(SleepTimer.inWindow(minuteOfDay = 23 * 60, start = 22 * 60, end = 6 * 60))
        assertTrue(SleepTimer.inWindow(minuteOfDay = 60, start = 22 * 60, end = 6 * 60))
        assertFalse(SleepTimer.inWindow(minuteOfDay = 12 * 60, start = 22 * 60, end = 6 * 60))
        assertTrue(SleepTimer.inWindow(minuteOfDay = 13 * 60, start = 12 * 60, end = 14 * 60))
        assertFalse(SleepTimer.inWindow(minuteOfDay = 15 * 60, start = 12 * 60, end = 14 * 60))
    }
}
