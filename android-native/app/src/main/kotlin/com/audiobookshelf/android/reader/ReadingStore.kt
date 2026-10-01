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
        val conflictUpdatedAt: Double? = null,
    ) {
        val pending get() = primary && revision > acknowledged
        val progress get() = if (pages > 0) ((page - 1).toDouble() / pages).coerceIn(0.0, 1.0) else 0.0
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
    @Synchronized fun publishable(account: AccountIdentity) = pending(account).filter { it.conflictPage == null }

    @Synchronized fun pendingAccounts() = entries.filter { it.pending && it.conflictPage == null }.map { it.account }.toSet()

    @Synchronized
    fun record(account: AccountIdentity, itemId: String, fileId: String, primary: Boolean, page: Int, pages: Int, now: Long = System.currentTimeMillis()) {
        val current = entry(account, itemId, fileId)
        val next = current?.copy(page = page, pages = pages, updatedAt = now.toDouble(), revision = current.revision + 1, primary = primary)
            ?: Entry(account, itemId, fileId, primary, page, pages, now.toDouble(), revision = 1)
        save(next)
    }

    /**
     * Applies the server's state when it is news: another device's page is adopted, or kept as a
     * conflict while this device has an unsent page. Returns true when the page changed.
     */
    @Synchronized
    fun adoptRemote(account: AccountIdentity, itemId: String, fileId: String, progress: MediaProgress?): Boolean {
        val location = progress?.ebookLocation?.trim() ?: return false
        val page = location.toIntOrNull()?.takeIf { it > 0 } ?: return false
        val updated = progress.lastUpdate ?: return false
        val current = entry(account, itemId, fileId)
        if (current == null) {
            save(Entry(account, itemId, fileId, primary = true, page = page, updatedAt = updated, remoteUpdatedAt = updated))
            return true
        }
        if (updated <= current.remoteUpdatedAt) return false
        if (location == current.page.toString() || location in current.unconfirmed) {
            save(current.copy(remoteUpdatedAt = updated))
            return false
        }
        if (current.pending) {
            save(current.copy(conflictPage = page, conflictUpdatedAt = updated))
            return false
        }
        save(current.copy(page = page, updatedAt = updated, primary = true, acknowledged = current.revision, remoteUpdatedAt = updated,
            unconfirmed = emptyList(), conflictPage = null, conflictUpdatedAt = null))
        return true
    }

    /** Decides from the server's current state whether [sending] may be published. */
    @Synchronized
    fun preflight(sending: Entry, server: MediaProgress?): Preflight {
        val current = entry(sending.account, sending.itemId, sending.fileId) ?: return Preflight.ALREADY_THERE
        val location = server?.ebookLocation?.trim()
        val updated = server?.lastUpdate
        if (location == null || updated == null || updated <= current.remoteUpdatedAt || location in current.unconfirmed) return Preflight.SEND
        if (location == sending.page.toString()) return Preflight.ALREADY_THERE
        adoptRemote(sending.account, sending.itemId, sending.fileId, server)
        return Preflight.CONFLICT
    }

    /** Notes that [sending]'s page is about to be sent, before the request can be applied. */
    @Synchronized
    fun sending(sending: Entry) {
        val current = entry(sending.account, sending.itemId, sending.fileId) ?: return
        val location = sending.page.toString()
        if (location !in current.unconfirmed) save(current.copy(unconfirmed = current.unconfirmed + location))
    }

    /** Records that the server holds [sent]'s page; [server] is its state afterwards, when known. */
    @Synchronized
    fun acknowledge(sent: Entry, server: MediaProgress?) {
        val current = entry(sent.account, sent.itemId, sent.fileId) ?: return
        val acknowledged = maxOf(current.acknowledged, minOf(sent.revision, current.revision))
        // A later write by another device is not this publication's result and stays news.
        val confirmed = server?.lastUpdate?.takeIf { server.ebookLocation?.trim() == sent.page.toString() }
        save(current.copy(
            acknowledged = acknowledged,
            remoteUpdatedAt = maxOf(current.remoteUpdatedAt, confirmed ?: 0.0),
            unconfirmed = if (acknowledged >= current.revision) emptyList() else current.unconfirmed,
        ))
    }

    /** The reader's answer to a conflict: publish this device's page, or go to the other device's. */
    @Synchronized
    fun resolveConflict(account: AccountIdentity, itemId: String, fileId: String, keepLocal: Boolean) {
        val current = entry(account, itemId, fileId) ?: return
        val page = current.conflictPage ?: return
        val updated = current.conflictUpdatedAt ?: current.remoteUpdatedAt
        save(if (keepLocal) current.copy(remoteUpdatedAt = updated, conflictPage = null, conflictUpdatedAt = null)
            else current.copy(page = page, updatedAt = updated, acknowledged = current.revision, remoteUpdatedAt = updated,
                unconfirmed = emptyList(), conflictPage = null, conflictUpdatedAt = null))
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
        return runCatching { AbsJson.decodeFromString(Document.serializer(), file.readText()).entries }
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
            val next = store.publishable(account).firstOrNull() ?: break
            try {
                when (store.preflight(next, remote.progress(next.itemId))) {
                    ReadingStore.Preflight.CONFLICT -> continue
                    ReadingStore.Preflight.ALREADY_THERE -> { store.acknowledge(next, null); continue }
                    ReadingStore.Preflight.SEND -> Unit
                }
                store.sending(next)
                remote.save(next.itemId, next.page.toString(), next.progress)
                store.acknowledge(next, runCatching { remote.progress(next.itemId) }.getOrNull())
                backoffMs = FIRST_RETRY_MS
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
