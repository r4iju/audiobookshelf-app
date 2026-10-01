package com.audiobookshelf.android.download

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.IOException

/**
 * A folder the user chose through the system picker. The app only reaches it through the persisted
 * grant, so a folder whose grant is gone counts as lost even while this process could still read it.
 */
class DownloadFolder(private val context: Context) {
    private val resolver: ContentResolver get() = context.contentResolver

    fun granted(tree: String): Boolean = resolver.persistedUriPermissions
        .any { it.uri.toString() == tree && it.isReadPermission && it.isWritePermission }

    /** Keeps access to a folder the picker returned; its name is shown wherever the folder is meant. */
    fun adopt(tree: Uri): String {
        resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        return name(tree)
    }

    /** Gives up a folder no longer used for downloads; an unknown grant is ignored. */
    fun release(tree: String) {
        runCatching { resolver.releasePersistableUriPermission(Uri.parse(tree), Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) }
    }

    fun name(tree: Uri): String = runCatching {
        resolver.query(root(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    }.getOrNull() ?: tree.lastPathSegment?.substringAfterLast(':')?.substringAfterLast('/') ?: "the chosen folder"

    /** Copies a finished file into `<tree>/<path...>/<name>`, replacing an earlier copy; returns the document. */
    fun place(tree: String, path: List<String>, name: String, mimeType: String, source: File): Uri {
        val treeUri = Uri.parse(tree)
        var parent = root(treeUri)
        for (segment in path.map(::safe)) parent = child(treeUri, parent, segment) ?: create(parent, DocumentsContract.Document.MIME_TYPE_DIR, segment)
        child(treeUri, parent, safe(name))?.let { DocumentsContract.deleteDocument(resolver, it) }
        val document = create(parent, mimeType, safe(name))
        try {
            resolver.openOutputStream(document, "w")!!.use { output -> source.inputStream().use { it.copyTo(output) } }
            if (size(document) != source.length()) throw IOException("The copy in the folder is incomplete")
        } catch (failure: Exception) {
            runCatching { DocumentsContract.deleteDocument(resolver, document) }
            throw failure as? IOException ?: IOException("The file could not be saved in the folder", failure)
        }
        return document
    }

    fun exists(document: String): Boolean = runCatching { size(Uri.parse(document)) != null }.getOrDefault(false)

    fun delete(document: String) {
        runCatching { DocumentsContract.deleteDocument(resolver, Uri.parse(document)) }
    }

    private fun size(document: Uri): Long? = resolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)
        ?.use { if (it.moveToFirst()) it.getLong(0) else null }

    private fun root(tree: Uri) = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun child(tree: Uri, parent: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            while (it.moveToNext()) if (it.getString(1) == name) return DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0))
        }
        return null
    }

    private fun create(parent: Uri, mimeType: String, name: String): Uri =
        DocumentsContract.createDocument(resolver, parent, mimeType, name) ?: throw IOException("The folder refused a new file")

    private fun safe(name: String) = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim().trimEnd('.').ifBlank { "Untitled" }.take(120)
}
