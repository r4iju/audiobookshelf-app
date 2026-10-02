package com.audiobookshelf.core

/** Maps whole-book positions to (file, offset) for multi-file items. All values are seconds. */
class Timeline(val tracks: List<AudioTrack>, val chapters: List<Chapter>) {
    data class Location(val trackIndex: Int, val offset: Double)

    private val starts: List<Double> = tracks.runningFold(0.0) { start, track -> start + track.duration }.dropLast(1)
        .mapIndexed { index, computed -> tracks[index].startOffset.takeIf { index == 0 || it > 0 } ?: computed }

    val duration: Double get() = if (tracks.isEmpty()) 0.0 else starts.last() + tracks.last().duration

    fun locate(position: Double): Location {
        if (tracks.isEmpty()) return Location(0, 0.0)
        val clamped = position.coerceIn(0.0, duration)
        val index = starts.indexOfLast { it <= clamped }.coerceAtLeast(0)
        return Location(index, (clamped - starts[index]).coerceIn(0.0, tracks[index].duration))
    }

    fun position(trackIndex: Int, offset: Double): Double =
        if (tracks.isEmpty()) 0.0 else (starts[trackIndex.coerceIn(0, tracks.lastIndex)] + offset).coerceIn(0.0, duration)

    fun chapterIndex(position: Double): Int = chapters.indexOfLast { it.start <= position + 0.0005 }.let {
        if (it < 0 && chapters.isNotEmpty()) 0 else it
    }

    fun chapterAt(position: Double): Chapter? = chapters.getOrNull(chapterIndex(position))
    fun chapterElapsed(position: Double): Double = chapterAt(position)?.let { (position - it.start).coerceAtLeast(0.0) } ?: position
    fun chapterDuration(position: Double): Double = chapterAt(position)?.let { it.end - it.start } ?: duration
}
