package com.audiobookshelf.android.playback

import android.util.Log
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.ListeningJournal
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Publishes journaled listening through `/api/session/local-all`. Each record is an absolute total
 * for a stable session ID, so a retry after a lost acknowledgment cannot double count.
 */
class ProgressSync(
    private val scope: CoroutineScope,
    private val journal: ListeningJournal,
    private val accounts: AccountStore,
    private val io: CoroutineDispatcher,
    private val report: com.audiobookshelf.android.data.Report = { _, _, _ -> },
) {
    private val lock = Mutex()
    private var retry: Job? = null
    private var backoffMs = FIRST_RETRY_MS
    private val failing = MutableStateFlow(false)
    /** True while the last publication attempt failed; unsent listening stays in the journal. */
    val pendingFailure: StateFlow<Boolean> = failing
    private val acknowledgedFor = MutableSharedFlow<AccountIdentity>(extraBufferCapacity = 8)
    /** Accounts whose server progress just changed through publication, so screens can refresh it. */
    val published: SharedFlow<AccountIdentity> = acknowledgedFor

    fun publishAll() {
        scope.launch {
            val accountsWithWork = withContext(io) { journal.pendingAccounts() }
            accountsWithWork.forEach { publish(it) }
        }
    }

    /** Unsent listening is retried with backoff while the process lives; relaunch and reconnect also retry. */
    private fun scheduleRetry() {
        if (retry?.isActive == true) return
        val wait = backoffMs
        backoffMs = (backoffMs * 2).coerceAtMost(MAX_RETRY_MS)
        retry = scope.launch {
            delay(wait)
            publishAll()
        }
    }

    suspend fun publish(account: AccountIdentity): Boolean = lock.withLock {
        val client = accounts.clientFor(account) ?: return@withLock false
        val pending = withContext(io) { journal.pending(account) }
        if (pending.isEmpty()) return@withLock true
        try {
            val acknowledged = client.syncLocal(pending.map { it.payload() })
            withContext(io) { pending.filter { it.id in acknowledged }.forEach(journal::acknowledge) }
            if (acknowledged.isNotEmpty()) acknowledgedFor.tryEmit(account)
            failing.value = acknowledged.size < pending.size
            if (failing.value) scheduleRetry() else backoffMs = FIRST_RETRY_MS
            !failing.value
        } catch (failure: Exception) {
            Log.i("AbsProgress", "Listening kept for retry: ${failure.javaClass.simpleName}")
            report(com.audiobookshelf.android.data.Diagnostics.Area.SYNC, "Listening could not be sent to ${account.server}; it is kept and retried", failure)
            failing.value = true
            if (failure is ApiError.SignInRequired) accounts.handle(failure) else scheduleRetry()
            false
        }
    }

    private companion object {
        const val FIRST_RETRY_MS = 5_000L
        const val MAX_RETRY_MS = 300_000L
    }
}
