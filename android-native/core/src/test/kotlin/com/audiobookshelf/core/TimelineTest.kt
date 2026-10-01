package com.audiobookshelf.core

import org.junit.Assert.assertEquals
import org.junit.Test

class TimelineTest {
    private val timeline = Timeline(
        listOf(AudioTrack(startOffset = 0.0, duration = 8.0), AudioTrack(startOffset = 8.0, duration = 12.0)),
        listOf(Chapter(0, 0.0, 8.0, "Opening"), Chapter(1, 8.0, 20.0, "Next chapter")),
    )

    @Test
    fun mapsWholeBookPositionsAcrossFileBoundaries() {
        assertEquals(Timeline.Location(0, 6.0), timeline.locate(6.0))
        assertEquals(Timeline.Location(1, 0.0), timeline.locate(8.0))
        assertEquals(Timeline.Location(1, 2.5), timeline.locate(10.5))
        assertEquals(Timeline.Location(1, 12.0), timeline.locate(99.0))
        assertEquals(Timeline.Location(0, 0.0), timeline.locate(-4.0))
        assertEquals(14.0, timeline.position(1, 6.0), 0.0)
        assertEquals(20.0, timeline.duration, 0.0)
    }

    @Test
    fun separatesChapterProgressFromBookProgress() {
        val chapter = timeline.chapterAt(11.0)!!
        assertEquals("Next chapter", chapter.title)
        assertEquals(3.0, timeline.chapterElapsed(11.0), 0.0)
        assertEquals(12.0, timeline.chapterDuration(11.0), 0.0)
        assertEquals("Opening", timeline.chapterAt(0.0)!!.title)
        assertEquals(1, timeline.chapterIndex(8.0))
    }
}
