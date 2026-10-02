package com.audiobookshelf.android.podcast

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * Feed episodes this device asked the server to download. The server reports only failures in
 * realtime, so a request stays pending until the episode appears on the item or a failure arrives.
 * Kept on disk so a relaunch still explains what is queued or failed.
 */
class PodcastRequests(private val file: File) {
    enum class State { PENDING, FAILED }

    @Serializable data class Record(
        val id: String,
        val account: AccountIdentity,
        val itemId: String,
        val enclosureId: String,
        val title: String,
        val state: State,
        val failedJobIds: List<String> = emptyList(),
    )

    @Serializable private data class Document(val version: Int, val records: List<Record>)

    /** False when the stored queue could not be read; the original file is left in place. Declared before [state], whose initializer sets it. */
    var writable = true; private set
    private val state = MutableStateFlow(read())
    val records: StateFlow<List<Record>> = state

    fun pending(account: AccountIdentity, itemId: String) = state.value.filter { it.account == account && it.itemId == itemId && it.state == State.PENDING }
    fun failures(account: AccountIdentity, itemId: String) = state.value.filter { it.account == account && it.itemId == itemId && it.state == State.FAILED }

    @Synchronized
    fun begin(account: AccountIdentity, itemId: String, episodes: List<Pair<String, String>>) {
        val next = state.value.toMutableList()
        for ((title, url) in episodes) {
            val key = identity(url)
            val index = next.indexOfFirst { it.account == account && it.itemId == itemId && it.enclosureId == key }
            if (index >= 0) next[index] = next[index].copy(state = State.PENDING, title = title)
            else next += Record(UUID.randomUUID().toString(), account, itemId, key, title, State.PENDING)
        }
        save(next)
    }

    @Synchronized
    fun reject(account: AccountIdentity, itemId: String, urls: List<String>) {
        val keys = urls.map(::identity).toSet()
        save(state.value.map { if (it.account == account && it.itemId == itemId && it.enclosureId in keys) it.copy(state = State.FAILED) else it })
    }

    /** Applies a failed server download once per job, even if the event is delivered twice. */
    @Synchronized
    fun receiveFailure(account: AccountIdentity, itemId: String, url: String, jobId: String) {
        val key = identity(url)
        val index = state.value.indexOfFirst { it.account == account && it.itemId == itemId && it.enclosureId == key }
        if (index < 0 || jobId in state.value[index].failedJobIds) return
        save(state.value.toMutableList().also { it[index] = it[index].copy(state = State.FAILED, failedJobIds = it[index].failedJobIds + jobId) })
    }

    /** Clears requests whose episodes are now on the server. */
    @Synchronized
    fun arrived(account: AccountIdentity, itemId: String, enclosureUrls: Collection<String>) {
        val present = enclosureUrls.map(::identity).toSet()
        val next = state.value.filterNot { it.account == account && it.itemId == itemId && it.enclosureId in present }
        if (next.size != state.value.size) save(next)
    }

    @Synchronized
    fun dismiss(id: String) = save(state.value.filterNot { it.id == id })

    private fun save(next: List<Record>) {
        check(writable) { "The download request list could not be read earlier, so it is not overwritten." }
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(1, next)).toByteArray())
        state.value = next
    }

    private fun read(): List<Record> {
        if (!file.exists()) return emptyList()
        return runCatching { AbsJson.decodeFromString(Document.serializer(), file.readText()).records }.getOrElse { writable = false; emptyList() }
    }

    companion object {
        fun identity(url: String): String = MessageDigest.getInstance("SHA-256").digest(url.trim().toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
