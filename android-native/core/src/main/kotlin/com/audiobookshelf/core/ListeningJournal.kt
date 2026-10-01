package com.audiobookshelf.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

@Serializable data class ListeningMedia(
    val libraryItemId: String,
    val episodeId: String?,
    val title: String,
    val author: String,
    val mediaType: String,
    val duration: Double,
    val startTime: Double,
    /** 0 direct play (streamed), 3 local (downloaded), matching the server's PlayMethod values. */
    val playMethod: Int = 0,
)

@Serializable data class ListeningRecord(
    val id: String,
    val account: AccountIdentity,
    val media: ListeningMedia,
    val deviceId: String,
    val startedAt: Double,
    val updatedAt: Double,
    val currentTime: Double,
    val timeListening: Double,
    val revision: Long,
    val acknowledged: Long,
    val closed: Boolean,
) {
    /** Body accepted by `/api/session/local-all`; listening is an absolute total for this session ID. */
    fun payload(): JsonObject = buildJsonObject {
        put("id", id)
        put("libraryItemId", media.libraryItemId)
        put("episodeId", media.episodeId?.let(::JsonPrimitive) ?: JsonNull)
        put("mediaType", media.mediaType)
        put("mediaMetadata", buildJsonObject { put("title", media.title); put("authorName", media.author) })
        put("displayTitle", media.title)
        put("displayAuthor", media.author)
        put("duration", media.duration)
        put("playMethod", media.playMethod)
        put("mediaPlayer", "exo-player")
        put("startTime", media.startTime)
        put("currentTime", currentTime)
        put("timeListening", timeListening)
        put("startedAt", startedAt)
        put("updatedAt", updatedAt)
    }
}

/**
 * Durable record of positions and absolute listening totals, written atomically before any
 * publication attempt. Records retire only once the revision actually sent is acknowledged.
 */
class ListeningJournal(private val file: File) {
    class Unreadable(cause: Throwable?) : Exception("Saved listening data could not be read. It is kept for recovery.", cause)

    @Serializable private data class Position(val account: AccountIdentity, val itemId: String, val episodeId: String?, val time: Double, val updatedAt: Double)
    @Serializable private data class Document(val version: Int, val records: List<ListeningRecord>, val positions: List<Position> = emptyList())

    private var records: List<ListeningRecord>
    private var positions: List<Position>

    init {
        if (file.exists()) {
            val saved = try {
                AbsJson.decodeFromString(Document.serializer(), file.readText())
            } catch (error: Exception) {
                throw Unreadable(error)
            }
            if (saved.version != 1 || saved.positions.any { !it.time.isFinite() || it.time < 0 || !it.updatedAt.isFinite() }) throw Unreadable(null)
            records = saved.records
            positions = saved.records.fold(saved.positions) { all, record -> remember(all, record.position()) }
        } else {
            records = emptyList(); positions = emptyList()
        }
    }

    @Synchronized
    fun begin(account: AccountIdentity, media: ListeningMedia, deviceId: String, now: Long = System.currentTimeMillis()): String {
        require(media.duration.isFinite() && media.duration > 0 && media.startTime.isFinite())
        val record = ListeningRecord(
            UUID.randomUUID().toString(), account, media, deviceId, now.toDouble(), now.toDouble(),
            media.startTime.coerceIn(0.0, media.duration), 0.0, revision = 1, acknowledged = 0, closed = false,
        )
        commit(records + record, remember(positions, record.position()))
        return record.id
    }

    @Synchronized
    fun record(id: String, position: Double, listened: Double, now: Long = System.currentTimeMillis()) {
        require(position.isFinite() && listened.isFinite() && listened >= 0)
        val index = records.indexOfFirst { it.id == id && !it.closed }
        require(index >= 0) { "No open listening record" }
        val current = records[index]
        val next = current.copy(
            currentTime = position.coerceIn(0.0, current.media.duration),
            timeListening = current.timeListening + listened,
            updatedAt = now.toDouble(),
            revision = current.revision + 1,
        )
        commit(records.toMutableList().also { it[index] = next }, remember(positions, next.position()))
    }

    @Synchronized
    fun finish(id: String) {
        val index = records.indexOfFirst { it.id == id && !it.closed }
        if (index < 0) return
        val closed = records[index].copy(closed = true)
        commit(records.toMutableList().also { if (closed.acknowledged == closed.revision) it.removeAt(index) else it[index] = closed })
    }

    @Synchronized
    fun pending(account: AccountIdentity): List<ListeningRecord> =
        records.filter { it.account == account && it.revision > it.acknowledged }.sortedWith(compareBy({ it.updatedAt }, { it.id }))

    @Synchronized
    fun pendingAccounts(): Set<AccountIdentity> = records.filter { it.revision > it.acknowledged }.map { it.account }.toSet()

    @Synchronized
    fun open(id: String): ListeningRecord? = records.firstOrNull { it.id == id }

    @Synchronized
    fun acknowledge(sent: ListeningRecord) {
        val index = records.indexOfFirst { it.id == sent.id && it.account == sent.account }
        if (index < 0) return
        val current = records[index]
        val next = current.copy(acknowledged = maxOf(current.acknowledged, minOf(sent.revision, current.revision)))
        commit(records.toMutableList().also { if (next.closed && next.acknowledged == next.revision) it.removeAt(index) else it[index] = next })
    }

    /** After process death, open records belong to no live player: close them so they can retire once published. */
    @Synchronized
    fun finishRecoveredSessions() {
        commit(records.map { it.copy(closed = true) }.filterNot { it.revision == it.acknowledged })
    }

    @Synchronized
    fun cachedPosition(account: AccountIdentity, itemId: String, episodeId: String?, newerThan: Double): Double? =
        positions.firstOrNull { it.account == account && it.itemId == itemId && it.episodeId == episodeId && it.updatedAt >= newerThan }?.time

    @Synchronized
    fun cachedUpdatedAt(account: AccountIdentity, itemId: String, episodeId: String?): Double? =
        positions.firstOrNull { it.account == account && it.itemId == itemId && it.episodeId == episodeId }?.updatedAt

    @Synchronized
    fun rememberRemotePosition(account: AccountIdentity, itemId: String, episodeId: String?, time: Double, updatedAt: Double) {
        require(time.isFinite() && time >= 0 && updatedAt.isFinite())
        commit(records, remember(positions, Position(account, itemId, episodeId, time, updatedAt)))
    }

    /** Forgets where this device last was in a title whose progress was discarded. */
    @Synchronized
    fun forgetPosition(account: AccountIdentity, itemId: String, episodeId: String?) {
        commit(records, positions.filterNot { it.account == account && it.itemId == itemId && it.episodeId == episodeId })
    }

    private fun ListeningRecord.position() = Position(account, media.libraryItemId, media.episodeId, currentTime, updatedAt)

    private fun remember(all: List<Position>, position: Position): List<Position> {
        val index = all.indexOfFirst { it.account == position.account && it.itemId == position.itemId && it.episodeId == position.episodeId }
        if (index < 0) return all + position
        return if (all[index].updatedAt <= position.updatedAt) all.toMutableList().also { it[index] = position } else all
    }

    private fun commit(nextRecords: List<ListeningRecord>, nextPositions: List<Position> = positions) {
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(1, nextRecords, nextPositions)).toByteArray())
        records = nextRecords
        positions = nextPositions
    }
}

/** Write-then-rename so a crash leaves either the previous or the next complete document. */
fun writeAtomically(file: File, data: ByteArray) {
    file.parentFile?.mkdirs()
    val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
    try {
        FileOutputStream(temporary).use { stream ->
            stream.write(data)
            stream.fd.sync()
        }
        if (!temporary.renameTo(file)) throw java.io.IOException("Could not replace ${file.name}")
    } finally {
        temporary.delete()
    }
}
