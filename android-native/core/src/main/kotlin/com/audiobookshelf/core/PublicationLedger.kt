package com.audiobookshelf.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.UnknownHostException
import java.util.UUID

/**
 * Progress writes that may still be applied by the server. Server 2.30 neither orders requests for a
 * session or title nor reports whether an earlier request has finished, so only the answer to the
 * request itself shows that its handler is done. A write is recorded before it is sent; one whose
 * answer never came (a lost connection, a gateway timeout, process death) stays recorded, and its
 * titles stay uncertain, until the user explicitly accepts the risk. A later write answered for the
 * same title, or seeing the server's state, does not show that the earlier one will not still land.
 */
class PublicationLedger(private val file: File) {
    @Serializable data class Title(val itemId: String, val episodeId: String?)

    enum class Kind { LISTENING, READING, FINISHED }

    @Serializable data class Attempt(
        val id: String,
        val account: AccountIdentity,
        val kind: Kind,
        val titles: List<Title>,
        /** For listening, the records exactly as sent, so their sessions are never sent with other totals. */
        val listening: List<ListeningRecord> = emptyList(),
        /** False while the request is out; true once it failed without showing that it was not applied. */
        val unanswered: Boolean = false,
    ) {
        fun holds(account: AccountIdentity, itemId: String, episodeId: String?) = this.account == account && Title(itemId, episodeId) in titles
    }

    @Serializable private data class Document(val version: Int = 1, val attempts: List<Attempt> = emptyList())

    class Unreadable : java.io.IOException("Records of unanswered progress writes could not be read. Resolve them in Diagnostics first.") {
        override fun getLocalizedMessage(): String? = ErrorText.of(this)
    }

    private val state = MutableStateFlow(emptyList<Attempt>())
    /** Writes that may still be applied, including any out right now. */
    val attempts: StateFlow<List<Attempt>> = state
    private val unreadableState = MutableStateFlow(false)
    /** True while the records cannot be read: any title may have a write that can still land. */
    val unreadable: StateFlow<Boolean> = unreadableState

    init {
        read()
    }

    /**
     * Sends a write for [titles], recorded first so that neither a lost answer nor process death can
     * leave it unaccounted for. Throws [Unreadable], sending nothing, while the records are unreadable.
     */
    suspend fun <T> publish(account: AccountIdentity, kind: Kind, titles: List<Title>, listening: List<ListeningRecord> = emptyList(), send: suspend () -> T): T {
        val attempt = issue(Attempt(UUID.randomUUID().toString(), account, kind, titles.distinct(), listening))
        val result = try {
            send()
        } catch (failure: Throwable) {
            if (mayStillApply(failure)) unanswered(attempt) else settle(attempt)
            throw failure
        }
        settle(attempt)
        return result
    }

    fun uncertain(account: AccountIdentity, itemId: String, episodeId: String?): Boolean =
        unreadableState.value || state.value.any { it.holds(account, itemId, episodeId) }

    /**
     * The user's explicit choice to go ahead although the title's earlier writes may still land.
     * Listening sent in those writes is first kept exactly as sent by [keep] (the journal's freeze),
     * since these records are what keeps it so; if that fails nothing is accepted and it is thrown.
     */
    @Synchronized
    fun accept(account: AccountIdentity, itemId: String, episodeId: String?, keep: (ListeningRecord) -> Unit = {}) {
        if (unreadableState.value) throw Unreadable()
        val title = Title(itemId, episodeId)
        val affected = state.value.filter { it.account == account && title in it.titles }
        affected.flatMap { it.listening }.forEach(keep)
        commit(state.value.mapNotNull { attempt ->
            if (attempt !in affected) attempt else attempt.copy(titles = attempt.titles - title).takeIf { it.titles.isNotEmpty() }
        })
    }

    /** Sets unreadable records aside at the user's explicit request, keeping the file beside the new one. */
    @Synchronized
    fun setAsideUnreadable(now: Long = System.currentTimeMillis()) {
        if (!unreadableState.value) return
        if (file.exists() && !file.renameTo(File(file.parentFile, "${file.name}.unreadable-$now"))) throw java.io.IOException("The unreadable records could not be set aside")
        state.value = emptyList()
        unreadableState.value = false
    }

    @Synchronized
    private fun issue(attempt: Attempt): Attempt {
        if (unreadableState.value) throw Unreadable()
        commit(state.value + attempt)
        return attempt
    }

    @Synchronized
    private fun settle(attempt: Attempt) = commit(state.value.filterNot { it.id == attempt.id })

    @Synchronized
    private fun unanswered(attempt: Attempt) = commit(state.value.map { if (it.id == attempt.id) it.copy(unanswered = true) else it })

    private fun commit(next: List<Attempt>) {
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(attempts = next)).toByteArray())
        state.value = next
    }

    private fun read() {
        if (!file.exists()) return
        try {
            val document = AbsJson.decodeFromString(Document.serializer(), file.readText())
            if (document.version != 1) throw IllegalStateException("Unknown version ${document.version}")
            // A write that was out when the process ended has no answer and never will.
            state.value = document.attempts.map { it.copy(unanswered = true) }
        } catch (failure: Exception) {
            unreadableState.value = true
        }
    }

    companion object {
        /**
         * Whether a write that failed this way may still be applied. Any answer from the server means
         * its handler has finished, except 502, 503 and 504: proxies send those when their connection to
         * the server failed or timed out, possibly after forwarding the write. A connection that was
         * never made carried nothing.
         */
        fun mayStillApply(failure: Throwable): Boolean = when (failure) {
            is ApiError.Http -> failure.status in 502..504
            is ApiError.SignInRequired, is ApiError.InvalidResponse, is ApiError.Untrusted -> false
            is ApiError.Offline -> generateSequence(failure.cause) { it.cause }.none { it is ConnectException || it is UnknownHostException || it is NoRouteToHostException }
            else -> true
        }
    }
}
