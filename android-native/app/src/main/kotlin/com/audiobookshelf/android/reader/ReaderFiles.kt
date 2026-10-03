package com.audiobookshelf.android.reader

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File
import java.security.MessageDigest

/** Saved primary and companion documents remain discoverable after an offline process restart. */
class ReaderFiles(private val directory: File) {
    @Serializable data class Entry(val account: AccountIdentity, val itemId: String, val fileId: String,
        val supplementary: Boolean, val title: String, val format: String) {
        val id get() = key(account, itemId, fileId, supplementary)
    }
    @Serializable private data class Index(val version: Int = 1, val files: List<Entry> = emptyList())
    private val index = File(directory, "index.json")
    var writable = true; private set
    private val mutable = MutableStateFlow(read())
    val entries: StateFlow<List<Entry>> = mutable
    fun file(account: AccountIdentity, itemId: String, fileId: String, supplementary: Boolean) = File(directory, key(account, itemId, fileId, supplementary) + ".bin")
    @Synchronized fun retain(entry: Entry) {
        check(writable) { "Unreadable saved document associations are preserved" }
        directory.mkdirs()
        save(mutable.value.filterNot { it.id == entry.id } + entry)
    }
    @Synchronized fun remove(entry: Entry) {
        check(writable) { "Unreadable saved document associations are preserved" }
        save(mutable.value.filterNot { it.id == entry.id })
        file(entry.account, entry.itemId, entry.fileId, entry.supplementary).delete()
    }
    private fun save(files: List<Entry>) {
        writeAtomically(index, AbsJson.encodeToString(Index.serializer(), Index(files = files)).toByteArray())
        mutable.value = files
    }
    private fun read(): List<Entry> {
        if (!index.exists()) return emptyList()
        return runCatching { AbsJson.decodeFromString(Index.serializer(), index.readText()).also { check(it.version == 1) }.files }
            .getOrElse { writable = false; emptyList() }
    }
    companion object {
        private fun key(account: AccountIdentity, itemId: String, fileId: String, supplementary: Boolean) =
            MessageDigest.getInstance("SHA-256").digest("${account.server}\n${account.userId}\n$itemId\n$fileId\n$supplementary".toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
