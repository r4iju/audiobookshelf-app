package com.audiobookshelf.android.download

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.AudioTrack
import com.audiobookshelf.core.Chapter
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File

/** Durable record of every download, independent of any screen or worker lifetime. */
class DownloadStore(private val file: File) {
    enum class State { QUEUED, RUNNING, FAILED, COMPLETE }

    /**
     * [ebookFileId] marks the item's ebook, kept beside the audio so it opens without the server.
     * [uri] is the file's document in the record's chosen folder, once it has been placed there.
     */
    @Serializable data class Part(val path: String, val name: String, val size: Long? = null, val mimeType: String? = null, val done: Boolean = false, val ebookFileId: String? = null, val ebookFormat: String? = null, val fileName: String? = null, val uri: String? = null)

    @Serializable data class Record(
        val id: String,
        val account: AccountIdentity,
        val itemId: String,
        val episodeId: String? = null,
        val title: String,
        val author: String = "",
        val mediaType: String,
        val duration: Double = 0.0,
        val chapters: List<Chapter> = emptyList(),
        val tracks: List<AudioTrack> = emptyList(),
        val parts: List<Part>,
        val directory: String,
        val state: State = State.QUEUED,
        val error: String? = null,
        val bytes: Long = 0,
        val createdAt: Long = System.currentTimeMillis(),
        val completedAt: Long? = null,
        /** The user allowed this download on a metered network. */
        val allowMetered: Boolean = false,
        /** Folder tree the files are saved in; [directory] then only holds the cover and unfinished parts. */
        val folder: String? = null,
        val folderName: String? = null,
    ) {
        /** Matches the UI's item key: the item id, or `item-episode` for an episode. */
        val key get() = if (episodeId == null) itemId else "$itemId-$episodeId"
        val audio get() = parts.filter { it.ebookFileId == null }
        val ebook get() = parts.firstOrNull { it.ebookFileId != null }
        val total get() = parts.mapNotNull { it.size }.takeIf { it.size == parts.size }?.sum()
    }

    @Serializable private data class Document(val version: Int = 1, val records: List<Record> = emptyList())

    private val state = MutableStateFlow(read())
    val records: StateFlow<List<Record>> = state

    @Synchronized fun get(id: String) = state.value.firstOrNull { it.id == id }

    @Synchronized fun put(record: Record) = save(state.value.filterNot { it.id == record.id } + record)

    @Synchronized fun update(id: String, transform: (Record) -> Record): Record? {
        val current = get(id) ?: return null
        val next = transform(current)
        save(state.value.map { if (it.id == id) next else it })
        return next
    }

    @Synchronized fun remove(id: String) = save(state.value.filterNot { it.id == id })

    /** Records are published only once they are on disk; a refused replacement leaves the previous manifest in place. */
    private fun save(next: List<Record>) {
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(records = next)).toByteArray())
        state.value = next
    }

    private fun read(): List<Record> {
        if (!file.exists()) return emptyList()
        return runCatching { AbsJson.decodeFromString(Document.serializer(), file.readText()).records }
            .getOrElse { error ->
                // Keep the unreadable original for diagnosis instead of overwriting it with an empty list.
                file.copyTo(File(file.path + ".unreadable-${System.currentTimeMillis()}"), overwrite = false)
                android.util.Log.w("AbsDownloads", "Download records unreadable", error)
                emptyList()
            }
    }
}
