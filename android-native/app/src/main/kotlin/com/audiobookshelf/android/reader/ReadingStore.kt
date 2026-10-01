package com.audiobookshelf.android.reader

import android.util.Log
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Reading positions on this device, written before any publication so a page survives process death
 * and offline use. Only the item's primary ebook is reading progress on the server; supplementary
 * documents keep their page here alone, as in the existing app.
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
    ) {
        val pending get() = primary && revision > acknowledged
        val progress get() = if (pages > 0) ((page - 1).toDouble() / pages).coerceIn(0.0, 1.0) else 0.0
    }

    @Serializable private data class Document(val version: Int = 1, val entries: List<Entry> = emptyList())

    /** False when stored positions could not be read; the file is kept and nothing is written over it. */
    var writable = true; private set
    private var entries: List<Entry> = read()

    @Synchronized fun entry(account: AccountIdentity, itemId: String, fileId: String) =
        entries.firstOrNull { it.account == account && it.itemId == itemId && it.fileId == fileId }

    @Synchronized fun pending(account: AccountIdentity) = entries.filter { it.account == account && it.pending }

    @Synchronized fun pendingAccounts() = entries.filter { it.pending }.map { it.account }.toSet()

    @Synchronized
    fun record(account: AccountIdentity, itemId: String, fileId: String, primary: Boolean, page: Int, pages: Int, now: Long = System.currentTimeMillis()) {
        val current = entry(account, itemId, fileId)
        val next = current?.copy(page = page, pages = pages, updatedAt = now.toDouble(), revision = current.revision + 1, primary = primary)
            ?: Entry(account, itemId, fileId, primary, page, pages, now.toDouble(), revision = 1)
        save(next)
    }

    @Synchronized
    fun acknowledge(sent: Entry) {
        val current = entry(sent.account, sent.itemId, sent.fileId) ?: return
        save(current.copy(acknowledged = maxOf(current.acknowledged, minOf(sent.revision, current.revision))))
    }

    /**
     * Adopts the server's page when it is newer. While this device still has an unpublished page the
     * server may be echoing an older publication from this device, so it is not adopted.
     */
    @Synchronized
    fun adoptRemote(account: AccountIdentity, itemId: String, fileId: String, progress: MediaProgress?): Boolean {
        val page = progress?.ebookLocation?.trim()?.toIntOrNull()?.takeIf { it > 0 } ?: return false
        val updated = progress.lastUpdate ?: return false
        val current = entry(account, itemId, fileId)
        if (current != null && (current.pending || current.updatedAt >= updated || current.page == page)) return false
        save(current?.copy(page = page, updatedAt = updated, primary = true, acknowledged = current.revision)
            ?: Entry(account, itemId, fileId, primary = true, page = page, updatedAt = updated))
        return true
    }

    private fun save(next: Entry) {
        check(writable) { "Saved reading positions could not be read, so they are not overwritten." }
        val updated = entries.filterNot { it.account == next.account && it.itemId == next.itemId && it.fileId == next.fileId } + next
        writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(entries = updated)).toByteArray())
        entries = updated
    }

    private fun read(): List<Entry> {
        if (!file.exists()) return emptyList()
        return runCatching { AbsJson.decodeFromString(Document.serializer(), file.readText()).entries }
            .getOrElse { writable = false; Log.w("AbsReading", "Reading positions unreadable", it); emptyList() }
    }
}

/**
 * Publishes the newest unpublished page per item, one request at a time per account, so a slow or
 * retried older page can never land after a newer one.
 */
class ReadingSync(private val scope: CoroutineScope, private val store: ReadingStore, private val accounts: AccountStore) {
    private val lock = Mutex()
    private var retry: Job? = null
    private var backoffMs = FIRST_RETRY_MS

    fun publishAll() {
        scope.launch { store.pendingAccounts().forEach { publish(it) } }
    }

    suspend fun publish(account: AccountIdentity) = lock.withLock {
        val client = accounts.clientFor(account) ?: return@withLock
        while (true) {
            val next = store.pending(account).firstOrNull() ?: break
            try {
                client.saveEbookProgress(next.itemId, next.page.toString(), next.progress)
                store.acknowledge(next)
                backoffMs = FIRST_RETRY_MS
            } catch (failure: Exception) {
                Log.i("AbsReading", "Reading position kept for retry: ${failure.javaClass.simpleName}")
                if (failure is ApiError.SignInRequired) accounts.handle(failure) else scheduleRetry()
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
