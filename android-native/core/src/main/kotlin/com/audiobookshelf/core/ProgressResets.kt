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
    suspend fun resetMissing(reset: ProgressResets.Reset) {}
    suspend fun committed(reset: ProgressResets.Reset) {}
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

    class Unreadable : java.io.IOException("Saved progress discards could not be read. Resolve them in Diagnostics first.") {
        override fun getLocalizedMessage(): String? = ErrorText.of(this)
    }

    private val state = MutableStateFlow(emptyList<Reset>())
    /** Resets requested and not yet complete. */
    val requested: StateFlow<List<Reset>> = state
    private val unreadableState = MutableStateFlow(false)
    /**
     * True while saved resets exist but cannot be read. Any title may be among them, so every title
     * counts as being reset until [abandonUnreadable] is chosen; the file is never overwritten meanwhile.
     */
    val unreadable: StateFlow<Boolean> = unreadableState
    private val running = Mutex()

    init {
        read()
    }

    /** Saves a reset of the title; an existing one for it is kept as it is. */
    @Synchronized
    fun request(account: AccountIdentity, itemId: String, episodeId: String?, now: Long = System.currentTimeMillis()): Reset {
        if (unreadableState.value) throw Unreadable()
        state.value.firstOrNull { it.matches(account, itemId, episodeId) }?.let { return it }
        return Reset(account, itemId, episodeId, now.toDouble()).also { commit(state.value + it) }
    }

    fun pending(account: AccountIdentity, itemId: String, episodeId: String?): Boolean =
        unreadableState.value || state.value.any { it.matches(account, itemId, episodeId) }

    fun pendingAccounts(): Set<AccountIdentity> = state.value.map { it.account }.toSet()

    /**
     * Withdraws a reset nothing has been done for yet, at the user's request; false, keeping it, once
     * the server progress was looked at, since this device may already have forgotten the title.
     */
    @Synchronized
    fun withdraw(account: AccountIdentity, itemId: String, episodeId: String?): Boolean {
        if (unreadableState.value) return false
        val reset = state.value.firstOrNull { it.matches(account, itemId, episodeId) } ?: return true
        if (reset.observed) return false
        commit(state.value - reset)
        return true
    }

    /**
     * Gives up the unreadable resets at the user's explicit request. The file is kept beside the
     * new one for recovery; titles play and publish again, and progress they were to discard stays.
     */
    @Synchronized
    fun abandonUnreadable(now: Long = System.currentTimeMillis()) {
        if (!unreadableState.value) return
        if (file.exists() && !file.renameTo(File(file.parentFile, "${file.name}.unreadable-$now"))) throw java.io.IOException("The unreadable discards could not be set aside")
        state.value = emptyList()
        unreadableState.value = false
    }

    /**
     * Completes the account's requested resets; true when none is left. False without trying while
     * the account is signed out. A failure is thrown after the reset is kept for a later attempt.
     */
    suspend fun complete(account: AccountIdentity): Boolean = running.withLock {
        if (unreadableState.value) return@withLock false
        val remote = remoteFor(account) ?: return@withLock false
        for (reset in state.value.filter { it.account == account }) exclusive(reset) { finish(remote, reset) }
        state.value.none { it.account == account }
    }

    private suspend fun finish(remote: ProgressRemote, requested: Reset) {
        val server = remote.progress(requested.itemId, requested.episodeId)
        val reset = if (requested.observed) requested else
            requested.copy(observed = true, progressId = server?.id, seenLastUpdate = server?.lastUpdate).also { if (!replace(requested, it)) return }
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
        if (reset.progressId == null) remote.resetMissing(reset)
        remote.committed(reset)
        synchronized(this) { commit(state.value.filterNot { it.matches(reset.account, reset.itemId, reset.episodeId) }) }
    }

    /** False when [old] is no longer requested, having been withdrawn meanwhile. */
    @Synchronized
    private fun replace(old: Reset, new: Reset): Boolean {
        if (old !in state.value) return false
        commit(state.value.map { if (it == old) new else it })
        return true
    }

    private fun commit(next: List<Reset>) {
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(resets = next)).toByteArray())
        state.value = next
    }

    private fun read() {
        if (!file.exists()) return
        try {
            val document = AbsJson.decodeFromString(Document.serializer(), file.readText())
            if (document.version != 1) throw IllegalStateException("Unknown version ${document.version}")
            state.value = document.resets
        } catch (failure: Exception) {
            unreadableState.value = true
        }
    }
}
