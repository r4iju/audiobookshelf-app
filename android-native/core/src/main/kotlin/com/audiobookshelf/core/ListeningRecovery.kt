package com.audiobookshelf.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Listening left by an ended process: sessions sent without an answer are frozen as sent and open
 * records are closed. Until that has been saved, nothing may play or publish, since either could
 * send a session with a total other than the one that may still land.
 */
class ListeningRecovery(private val journal: ListeningJournal, private val publications: PublicationLedger) {
    private val problemState = MutableStateFlow<Exception?>(null)
    /** Why recovery could not be saved, or null; it is retried by [run]. */
    val problem: StateFlow<Exception?> = problemState
    @Volatile private var done = false

    /** Saves the recovery unless done already; true once it is saved. */
    @Synchronized
    fun run(): Boolean {
        if (done) return true
        try {
            publications.attempts.value.flatMap { it.listening }.forEach(journal::freeze)
            journal.finishRecoveredSessions()
            done = true
            problemState.value = null
        } catch (failure: Exception) {
            problemState.value = failure
        }
        return done
    }
}
