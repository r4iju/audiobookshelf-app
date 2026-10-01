package com.audiobookshelf.android.playback

import android.util.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Owns listening that has left the player but is not yet in the journal, per journal record, until a
 * write succeeds. Nothing that depends on a record being complete (finishing it, publishing it, closing
 * its server session) runs before its listening is written, so a session that stops, switches account
 * or advances its queue while storage refuses writes keeps its listening and is retried.
 */
class ListeningWriter(
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher,
    private val write: (recordId: String, position: Double, listened: Double) -> Unit,
    private val finish: (recordId: String) -> Unit,
) {
    private class Pending(var position: Double, var listened: Double, var dirty: Boolean) {
        var finishing = false
        val afterWrite = mutableListOf<suspend () -> Unit>()
        val afterFinish = mutableListOf<suspend () -> Unit>()
    }

    private val pending = LinkedHashMap<String, Pending>()
    private val lock = Mutex()
    private var retry: Job? = null
    private var backoffMs = FIRST_RETRY_MS
    private val failingState = MutableStateFlow<Set<String>>(emptySet())
    /** Records whose listening could not be written yet. */
    val failing: StateFlow<Set<String>> = failingState

    /** Adds [listened] seconds ending at [position]; [then] runs once this is in the journal. */
    fun record(recordId: String, position: Double, listened: Double, then: (suspend () -> Unit)? = null) {
        synchronized(pending) {
            val entry = pending.getOrPut(recordId) { Pending(position, 0.0, dirty = true) }
            entry.position = position
            entry.listened += listened
            entry.dirty = true
            then?.let(entry.afterWrite::add)
        }
        drain()
    }

    /** Completes [recordId] after its listening is written; [then] runs only once the record is finished. */
    fun finish(recordId: String, then: suspend () -> Unit) {
        synchronized(pending) {
            val entry = pending.getOrPut(recordId) { Pending(0.0, 0.0, dirty = false) }
            entry.finishing = true
            entry.afterFinish += then
        }
        drain()
    }

    /** Retries unsaved listening now instead of at the next backoff. */
    fun retryNow() = drain()

    private fun drain() {
        scope.launch(io) {
            lock.withLock {
                val ids = synchronized(pending) { pending.keys.toList() }
                var failed = false
                for (id in ids) failed = !settle(id) || failed
                if (failed) scheduleRetry() else backoffMs = FIRST_RETRY_MS
            }
        }
    }

    /** Writes and, when asked, finishes one record; false when the journal refused and work remains. */
    private suspend fun settle(id: String): Boolean {
        // Callbacks are taken together with the data they wait for; later ones wait for a later write.
        val (snapshot, waiting) = synchronized(pending) {
            val entry = pending[id] ?: return true
            Triple(entry.position, entry.listened, entry.dirty) to entry.afterWrite.toList()
        }
        val (position, listened, dirty) = snapshot
        try {
            if (dirty) write(id, position, listened)
        } catch (failure: Exception) {
            Log.e(TAG, "Listening kept for retry", failure)
            failingState.value = failingState.value + id
            return false
        }
        synchronized(pending) {
            val entry = pending.getValue(id)
            entry.listened -= listened
            entry.dirty = entry.listened > 0 || entry.position != position
            entry.afterWrite.removeAll(waiting)
        }
        waiting.forEach { scope.launch { runCatching { it() } } }
        val finishing = synchronized(pending) { pending.getValue(id).let { it.finishing && !it.dirty } }
        if (finishing) {
            try {
                finish(id)
            } catch (failure: Exception) {
                Log.e(TAG, "Listening session kept open for retry", failure)
                failingState.value = failingState.value + id
                return false
            }
            val after = synchronized(pending) { pending.remove(id)?.afterFinish.orEmpty() }
            after.forEach { scope.launch { runCatching { it() } } }
        }
        failingState.value = failingState.value - id
        return true
    }

    /** Called with [lock] held, so only one retry is ever waiting. */
    private fun scheduleRetry() {
        if (retry?.isActive == true) return
        val wait = backoffMs
        backoffMs = (backoffMs * 2).coerceAtMost(MAX_RETRY_MS)
        // The handle is cleared before draining, so a drain that fails again can schedule the next retry.
        retry = scope.launch { delay(wait); lock.withLock { retry = null }; drain() }
    }

    private companion object {
        const val TAG = "AbsPlayback"
        const val FIRST_RETRY_MS = 1_000L
        const val MAX_RETRY_MS = 60_000L
    }
}
