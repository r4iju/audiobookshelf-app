package com.audiobookshelf.android.data

import android.util.Log
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File

/** Where a component reports a failure for the diagnostics screen. */
typealias Report = (area: Diagnostics.Area, message: String, failure: Throwable?) -> Unit

/**
 * Recent connection, media and synchronization failures, kept on this device for the diagnostics
 * screen. Entries are redacted before they are stored, so no credential ever reaches the file or the
 * screen, even when an exception message quotes a request.
 */
class Diagnostics(private val file: File) {
    enum class Area { CONNECTION, MEDIA, SYNC, STORAGE }

    @Serializable data class Entry(val at: Long, val area: Area, val message: String)

    @Serializable private data class Document(val version: Int = 1, val entries: List<Entry> = emptyList())

    private val state = MutableStateFlow(read())
    val entries: StateFlow<List<Entry>> = state

    @Synchronized
    fun record(area: Area, message: String, failure: Throwable? = null) {
        val detail = failure?.let { listOfNotNull(it.javaClass.simpleName, it.message).joinToString(": ") }
        val entry = Entry(System.currentTimeMillis(), area, redact(if (detail != null) "$message ($detail)" else message))
        val next = (listOf(entry) + state.value).take(LIMIT)
        state.value = next
        // Diagnostics must never break the flow that is failing; an unwritable file only loses history.
        runCatching { writeAtomically(file, AbsJson.encodeToString(Document.serializer(), Document(entries = next)).toByteArray()) }
            .onFailure { Log.i("AbsDiagnostics", "Diagnostics not saved: ${it.javaClass.simpleName}") }
    }

    @Synchronized
    fun clear() {
        state.value = emptyList()
        runCatching { file.delete() }
    }

    private fun read(): List<Entry> = runCatching {
        if (file.exists()) AbsJson.decodeFromString(Document.serializer(), file.readText()).entries else emptyList()
    }.getOrDefault(emptyList())

    companion object {
        private const val LIMIT = 100
        private val bearer = Regex("(?i)bearer\\s+[^\\s,;\"']+")
        private val jwt = Regex("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]*")
        private val parameter = Regex("(?i)\\b(token|access_token|refresh_token|accessToken|refreshToken|password|code|state|code_verifier|secret)=[^&\\s\"']*")
        private val field = Regex("(?i)\"(token|accessToken|refreshToken|password|secret)\"\\s*:\\s*\"[^\"]*\"")

        /** Removes bearer tokens, JWTs and credential-bearing query or JSON fields. */
        fun redact(text: String): String = text
            .replace(bearer, "[credential hidden]")
            .replace(jwt, "[credential hidden]")
            .replace(parameter, "[credential hidden]")
            .replace(field, "[credential hidden]")
    }
}
