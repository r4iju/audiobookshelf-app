package com.audiobookshelf.android.reader

import android.util.Log
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Reading positions on this device, written before any publication so a page survives process death
 * and offline use. Only the item's primary ebook is reading progress on the server; supplementary
 * documents keep their page here alone, as in the existing app.
 *
 * Each primary entry remembers the server state it last agreed with ([Entry.remoteUpdatedAt]) and the
 * pages it sent without a confirmed answer ([Entry.unconfirmed]). A server change that is neither came
 * from another device; while this device also has an unsent page, neither side silently wins and the
 * reader is asked ([Entry.conflictPage]).
 */
class ReadingStore(private val file: File) {
    @Serializable data class Entry(
        val account: AccountIdentity,
        val itemId: String,
        /** Library file ino of the document. */
        val fileId: String,
        val primary: Boolean,
        val page: Int,
        val pages: Int = 0,
        val updatedAt: Double,
        val revision: Long = 0,
        val acknowledged: Long = 0,
        /** Server `lastUpdate` of the newest server state this entry already accounts for. */
        val remoteUpdatedAt: Double = 0.0,
        /** Locations sent whose outcome is unknown, so their echo is recognised as this device's own. */
        val unconfirmed: List<String> = emptyList(),
        /** A newer page from another device, seen while this device's page was still unsent. */
        val conflictPage: Int? = null,
        /** Set for any such conflict, including a position this reader cannot show as a page. */
        val conflictUpdatedAt: Double? = null,
        /** The other device's position when it is not a page number, such as another format's location. */
        val conflictLocation: String? = null,
        val savedLocation: String? = null,
        val savedProgress: Double? = null,
    ) {
        val pending get() = primary && revision > acknowledged
        val inConflict get() = conflictUpdatedAt != null || conflictPage != null
        val location get() = savedLocation ?: page.toString()
        val progress get() = savedProgress ?: if (pages > 0) ((page - 1).toDouble() / pages).coerceIn(0.0, 1.0) else 0.0
    }

    @Serializable private data class Document(val version: Int = 1, val entries: List<Entry> = emptyList())

    enum class Preflight { SEND, ALREADY_THERE, CONFLICT }

    /** False when stored positions could not be read; the file is kept and nothing is written over it. */
    var writable = true; private set
    private var entries: List<Entry> = read()
    private val revisions = MutableStateFlow(0)
    /** Changes whenever an entry changes, for screens that show a conflict. */
    val changes: StateFlow<Int> = revisions

    @Synchronized fun entry(account: AccountIdentity, itemId: String, fileId: String) =
        entries.firstOrNull { it.account == account && it.itemId == itemId && it.fileId == fileId }

    @Synchronized fun pending(account: AccountIdentity) = entries.filter { it.account == account && it.pending }

    /** Unsent pages that may be published; a page in conflict waits for the reader's choice. */
    @Synchronized fun publishable(account: AccountIdentity) = pending(account).filterNot { it.inConflict }

    @Synchronized fun pendingAccounts() = entries.filter { it.pending && !it.inConflict }.map { it.account }.toSet()

    @Synchronized
    fun record(account: AccountIdentity, itemId: String, fileId: String, primary: Boolean, page: Int, pages: Int, now: Long = System.currentTimeMillis()) {
        val current = entry(account, itemId, fileId)
        val next = current?.copy(savedLocation = null, savedProgress = null, page = page, pages = pages, updatedAt = now.toDouble(), revision = current.revision + 1, primary = primary)
            ?: Entry(account, itemId, fileId, primary, page, pages, now.toDouble(), revision = 1)
        save(next)
    }

    @Synchronized
    fun recordLocation(account: AccountIdentity, itemId: String, fileId: String, primary: Boolean, location: String, progress: Double) {
        require(location.isNotBlank() && progress.isFinite())
        val current = entry(account, itemId, fileId)
        val next = current?.copy(savedLocation = location, savedProgress = progress.coerceIn(0.0, 1.0),
            updatedAt = System.currentTimeMillis().toDouble(), revision = current.revision + 1, primary = primary)
            ?: Entry(account, itemId, fileId, primary, page = location.toIntOrNull() ?: 1,
                updatedAt = System.currentTimeMillis().toDouble(), revision = 1, savedLocation = location, savedProgress = progress.coerceIn(0.0, 1.0))
        save(next)
    }

    /** An exported local position has not been confirmed by this client's server, so keep it pending. */
    @Synchronized
    fun adoptLegacy(account: AccountIdentity, itemId: String, location: String, progress: Double?, updatedAt: Long) {
        if (location.isBlank() || entry(account, itemId, "primary") != null) return
        val page = location.toIntOrNull()?.takeIf { it > 0 }
        save(Entry(account, itemId, "primary", true, page ?: 1, updatedAt = updatedAt.toDouble(), revision = 1,
            savedLocation = location.takeIf { page == null }, savedProgress = progress))
    }

    /**
     * Applies the server's state when it is news: another device's page is adopted, or kept as a
     * conflict while this device has an unsent page. Returns true when the page changed.
     */
    @Synchronized
    fun adoptRemote(account: AccountIdentity, itemId: String, fileId: String, progress: MediaProgress?): Boolean {
        val location = progress?.ebookLocation?.trim()?.takeIf { it.isNotEmpty() } ?: return false
        val updated = progress.lastUpdate ?: return false
        val page = location.toIntOrNull()?.takeIf { it > 0 }
        val current = entry(account, itemId, fileId)
        if (current == null) {
            save(Entry(account, itemId, fileId, primary = true, page = page ?: 1, updatedAt = updated, remoteUpdatedAt = updated, savedLocation = location.takeIf { page == null }, savedProgress = progress.ebookProgress))
            return true
        }
        if (updated <= current.remoteUpdatedAt) return false
        if (location == current.location || location in current.unconfirmed) {
            save(current.copy(remoteUpdatedAt = updated))
            return false
        }
        if (current.pending) {
            // Kept until the reader decides, so it is neither overwritten nor asked about again and again.
            save(current.copy(conflictPage = page, conflictUpdatedAt = updated, conflictLocation = location.takeIf { page == null }))
            return false
        }
        // Opaque locations stay intact until the matching reader can interpret them.
        save(current.copy(page = page ?: 1, savedLocation = location.takeIf { page == null }, savedProgress = progress.ebookProgress, updatedAt = updated, primary = true, acknowledged = current.revision, remoteUpdatedAt = updated,
            unconfirmed = emptyList(), conflictPage = null, conflictUpdatedAt = null, conflictLocation = null))
        return true
    }

    /** Decides from the server's current state whether [sending] may be published. */
    @Synchronized
    fun preflight(sending: Entry, server: MediaProgress?): Preflight {
        val current = entry(sending.account, sending.itemId, sending.fileId) ?: return Preflight.ALREADY_THERE
        val location = server?.ebookLocation?.trim()
        val updated = server?.lastUpdate
        if (location == null || updated == null || updated <= current.remoteUpdatedAt || location in current.unconfirmed) return Preflight.SEND
        if (location == sending.location) return Preflight.ALREADY_THERE
        adoptRemote(sending.account, sending.itemId, sending.fileId, server)
        return Preflight.CONFLICT
    }

    /** Notes that [sending]'s page is about to be sent, before the request can be applied. */
    @Synchronized
    fun sending(sending: Entry) {
        val current = entry(sending.account, sending.itemId, sending.fileId) ?: return
        val location = sending.location
        if (location !in current.unconfirmed) save(current.copy(unconfirmed = current.unconfirmed + location))
    }

    /** Records that the server holds [sent]'s page; [server] is its state afterwards, when known. */
    @Synchronized
    fun acknowledge(sent: Entry, server: MediaProgress?) {
        val current = entry(sent.account, sent.itemId, sent.fileId) ?: return
        val acknowledged = maxOf(current.acknowledged, minOf(sent.revision, current.revision))
        // A later write by another device is not this publication's result and stays news.
        val confirmed = server?.lastUpdate?.takeIf { server.ebookLocation?.trim() == sent.location }
        save(current.copy(
            acknowledged = acknowledged,
            remoteUpdatedAt = maxOf(current.remoteUpdatedAt, confirmed ?: 0.0),
            unconfirmed = if (acknowledged >= current.revision) emptyList() else current.unconfirmed,
        ))
    }

    /**
     * The reader's answer to a conflict: publish this device's page, or leave the other device's position
     * on the server, going to it when it is a page.
     */
    @Synchronized
    fun resolveConflict(account: AccountIdentity, itemId: String, fileId: String, keepLocal: Boolean) {
        val current = entry(account, itemId, fileId)?.takeIf { it.inConflict } ?: return
        val updated = current.conflictUpdatedAt ?: current.remoteUpdatedAt
        val resolved = current.copy(remoteUpdatedAt = updated, conflictPage = null, conflictUpdatedAt = null, conflictLocation = null)
        save(if (keepLocal) resolved
            else resolved.copy(page = current.conflictPage ?: current.page, savedLocation = current.conflictLocation, savedProgress = null, updatedAt = updated, acknowledged = current.revision, unconfirmed = emptyList()))
    }

    /** Forgets the item's reading progress after it was discarded; supplementary documents keep their page. */
    @Synchronized
    fun forget(account: AccountIdentity, itemId: String) {
        check(writable) { "Saved reading positions could not be read, so they are not overwritten." }
        val updated = entries.filterNot { it.account == account && it.itemId == itemId && it.primary }
        if (updated.size == entries.size) return
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(entries = updated)).toByteArray())
        entries = updated
        revisions.value += 1
    }

    private fun save(next: Entry) {
        check(writable) { "Saved reading positions could not be read, so they are not overwritten." }
        val updated = entries.filterNot { it.account == next.account && it.itemId == next.itemId && it.fileId == next.fileId } + next
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(entries = updated)).toByteArray())
        entries = updated
        revisions.value += 1
    }

    private fun read(): List<Entry> {
        if (!file.exists()) return emptyList()
        return runCatching { AbsJson.decodeFromString(Document.serializer(), file.readText()).also { check(it.version == 1) }.entries }
            .getOrElse { writable = false; Log.w("AbsReading", "Reading positions unreadable", it); emptyList() }
    }
}

/** The server's reading progress for one account. */
interface ReadingRemote {
    suspend fun progress(itemId: String): MediaProgress?
    suspend fun save(itemId: String, location: String, progress: Double)
}

/**
 * Publishes the newest unpublished page per item, one request at a time per account, so a slow or
 * retried older page can never land after a newer one. Each publication first reads the server, so a
 * newer page from another device is never overwritten without the reader's choice.
 */
class ReadingSync(
    private val scope: CoroutineScope,
    private val store: ReadingStore,
    private val remoteFor: (AccountIdentity) -> ReadingRemote?,
    private val onSignInRequired: (ApiError.SignInRequired) -> Unit,
    private val report: com.audiobookshelf.android.data.Report = { _, _, _ -> },
    /**
     * Runs one publication only when the account's listening allows it, returning false otherwise.
     * Legacy servers time audio and reading progress together, so listening decides when reading may go.
     */
    private val listeningGate: suspend (AccountIdentity, suspend () -> Unit) -> Boolean = { _, publication -> publication(); true },
    /** True while the title's progress is being discarded; its pages wait and other titles go ahead. */
    private val held: (AccountIdentity, String) -> Boolean = { _, _ -> false },
) {
    private val lock = Mutex()
    private var retry: Job? = null
    private var backoffMs = FIRST_RETRY_MS

    fun publishAll() {
        scope.launch { store.pendingAccounts().forEach { publish(it) } }
    }

    suspend fun publish(account: AccountIdentity) = lock.withLock {
        val remote = remoteFor(account) ?: return@withLock
        while (true) {
            if (store.publishable(account).none { !held(account, it.itemId) }) break
            try {
                // The page is chosen inside the gate: a progress reset that held it may have forgotten the page meanwhile.
                var chosen: ReadingStore.Entry? = null
                val allowed = listeningGate(account) {
                    val next = store.publishable(account).firstOrNull { !held(account, it.itemId) } ?: return@listeningGate
                    chosen = next
                    when (store.preflight(next, remote.progress(next.itemId))) {
                        ReadingStore.Preflight.CONFLICT -> Unit
                        ReadingStore.Preflight.ALREADY_THERE -> store.acknowledge(next, null)
                        ReadingStore.Preflight.SEND -> {
                            store.sending(next)
                            remote.save(next.itemId, next.location, next.progress)
                            store.acknowledge(next, runCatching { remote.progress(next.itemId) }.getOrNull())
                        }
                    }
                }
                // Listening is open or unsent; publication resumes when it ends.
                if (!allowed) break
                val next = chosen ?: break
                backoffMs = FIRST_RETRY_MS
                // A page that is still publishable unchanged would only be asked about again; wait for a retry.
                if (store.publishable(account).any { it.itemId == next.itemId && it.fileId == next.fileId && it.revision == next.revision }) { scheduleRetry(); break }
            } catch (failure: Exception) {
                Log.i("AbsReading", "Reading position kept for retry: ${failure.javaClass.simpleName}")
                report(com.audiobookshelf.android.data.Diagnostics.Area.SYNC, "Reading position could not be sent to ${account.server}; it is kept and retried", failure)
                if (failure is ApiError.SignInRequired) onSignInRequired(failure) else scheduleRetry()
                break
            }
        }
    }

    private fun scheduleRetry() {
        if (retry?.isActive == true) return
        val wait = backoffMs
        backoffMs = (backoffMs * 2).coerceAtMost(MAX_RETRY_MS)
        retry = scope.launch { delay(wait); publishAll() }
    }

    private companion object {
        const val FIRST_RETRY_MS = 1_000L
        const val MAX_RETRY_MS = 120_000L
    }
}
