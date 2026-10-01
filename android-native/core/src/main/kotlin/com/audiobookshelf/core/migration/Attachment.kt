package com.audiobookshelf.core.migration

import com.audiobookshelf.core.LibraryItem

object Attachment {
    /** Staged files in the order of the server item's tracks (null where none was imported), and its ebook; [problem] when they do not correspond. */
    data class Match(val audio: List<StagedFile?>, val ebook: StagedFile?, val problem: String?)

    fun match(title: ImportedTitle, item: LibraryItem, episodeId: String?): Match {
        val tracks = if (episodeId != null) listOfNotNull(item.media.episodes.firstOrNull { it.id == episodeId }?.audioTrack)
            else item.media.tracks.sortedBy { it.index ?: 0 }
        val legacy = title.audio
        val audio: List<StagedFile?> = when {
            // Only the ebook was downloaded; the title's audio was never asked for.
            legacy.isEmpty() -> emptyList()
            // A running download recorded the server's own 1-based track index, which listings may omit.
            title.partial -> tracks.mapIndexed { position, track -> legacy.firstOrNull { it.trackIndex != null && it.trackIndex == (track.index ?: (position + 1)) } }
            legacy.size == tracks.size -> legacy
            else -> return Match(emptyList(), null, "Its audio files changed on the server since the previous app downloaded it.")
        }
        if (title.partial && legacy.any { file -> file !in audio }) return Match(emptyList(), null, "Its audio files changed on the server since the previous app downloaded it.")
        val ebook = title.ebook
        val serverEbook = item.media.ebookFile.takeIf { episodeId == null }
        if (ebook != null && (serverEbook == null || serverEbook.format != ebook.ebookFormat || ebook.ebookIno != null && ebook.ebookIno != serverEbook.ino)) {
            return Match(emptyList(), null, "Its ebook changed on the server since the previous app downloaded it.")
        }
        return Match(audio, ebook, null)
    }
}
