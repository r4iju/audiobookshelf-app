package com.audiobookshelf.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.io.File

/** The server calls a progress reset needs, for one account. */
interface ProgressRemote {
    suspend fun progress(itemId: String, episodeId: String?): MediaProgress?
    suspend fun remove(progressId: String)
}

/**
 * Discards a title's progress on the server and on this device. A reset is saved before anything is
 * changed and stays until the server progress is gone and this device has forgotten the title, so a
 * failure, a lost response or a restart resumes it for the account that asked, never another one.
 *
 * [exclusive] runs a step only once the title's listening is on the server and while no reading
 * write or playback start can interleave; it returns false, running nothing, while that is not yet
 * possible. [cleanup] durably forgets the title on this device as of the given time.
 */
class ProgressResets(
    private val file: File,
    private val remoteFor: (AccountIdentity) -> ProgressRemote?,
    private val exclusive: suspend (Reset, suspend () -> Unit) -> Boolean,
    private val cleanup: (Reset, at: Double) -> Unit,
) {
    @Serializable data class Reset(
        val account: AccountIdentity,
        val itemId: String,
        val episodeId: String?,
        val requestedAt: Double,
        /** Set once the server progress to discard has been seen, before anything is deleted. */
        val observed: Boolean = false,
        val progressId: String? = null,
        val seenLastUpdate: Double? = null,
    ) {
        /**
         * The device forgets the title as of the later of the request and the server's last update
         * before the delete, so no server snapshot from before the delete counts as newer, whatever
         * the difference between the two clocks.
         */
        val resetAt get() = maxOf(requestedAt, seenLastUpdate ?: 0.0)

        fun matches(account: AccountIdentity, itemId: String, episodeId: String?) =
            this.account == account && this.itemId == itemId && this.episodeId == episodeId
    }

    @Serializable private data class Document(val version: Int = 1, val resets: List<Reset> = emptyList())

    private val state = MutableStateFlow(read())
    /** Resets requested and not yet complete. */
    val requested: StateFlow<List<Reset>> = state
    private val running = Mutex()

    /** Saves a reset of the title; an existing one for it is kept as it is. */
    @Synchronized
    fun request(account: AccountIdentity, itemId: String, episodeId: String?, now: Long = System.currentTimeMillis()): Reset {
        state.value.firstOrNull { it.matches(account, itemId, episodeId) }?.let { return it }
        return Reset(account, itemId, episodeId, now.toDouble()).also { commit(state.value + it) }
    }

    fun pending(account: AccountIdentity, itemId: String, episodeId: String?): Boolean = state.value.any { it.matches(account, itemId, episodeId) }

    fun pendingAccounts(): Set<AccountIdentity> = state.value.map { it.account }.toSet()

    /**
     * Completes the account's requested resets; true when none is left. False without trying while
     * the account is signed out. A failure is thrown after the reset is kept for a later attempt.
     */
    suspend fun complete(account: AccountIdentity): Boolean = running.withLock {
        val remote = remoteFor(account) ?: return@withLock false
        for (reset in state.value.filter { it.account == account }) exclusive(reset) { finish(remote, reset) }
        state.value.none { it.account == account }
    }

    private suspend fun finish(remote: ProgressRemote, requested: Reset) {
        val server = remote.progress(requested.itemId, requested.episodeId)
        val reset = if (requested.observed) requested else
            requested.copy(observed = true, progressId = server?.id, seenLastUpdate = server?.lastUpdate).also { replace(requested, it) }
        cleanup(reset, reset.resetAt)
        // Progress updated after the first look was made after the reset, for example by another
        // device while this one had not yet learned that its delete succeeded.
        val id = server?.id
        if (id != null && id == reset.progressId && (server.lastUpdate ?: 0.0) <= (reset.seenLastUpdate ?: 0.0)) {
            try {
                remote.remove(id)
            } catch (gone: ApiError.Http) {
                if (gone.status != 404) throw gone
            }
        }
        synchronized(this) { commit(state.value.filterNot { it.matches(reset.account, reset.itemId, reset.episodeId) }) }
    }

    @Synchronized
    private fun replace(old: Reset, new: Reset) = commit(state.value.map { if (it == old) new else it })

    private fun commit(next: List<Reset>) {
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(resets = next)).toByteArray())
        state.value = next
    }

    private fun read(): List<Reset> {
        if (!file.exists()) return emptyList()
        return try {
            AbsJson.decodeFromString(Document.serializer(), file.readText()).resets
        } catch (unreadable: Exception) {
            // Kept for recovery instead of being overwritten by the next request.
            file.renameTo(File(file.parentFile, "${file.name}.unreadable-${System.currentTimeMillis()}"))
            emptyList()
        }
    }
}
