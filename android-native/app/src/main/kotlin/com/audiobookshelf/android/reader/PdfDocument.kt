package com.audiobookshelf.android.reader

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.ext.SdkExtensions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.io.File

/** A rendered page. [links] are goto-link areas in the bitmap's coordinates with their 1-based target page. */
class RenderedPage(val bitmap: Bitmap, val text: String, val links: List<Pair<RectF, Int>>)

/** One open PDF. The platform renderer allows one open page at a time, so all access is serialized. */
class PdfDocument private constructor(private val descriptor: ParcelFileDescriptor, private val renderer: PdfRenderer) : Closeable {
    private val lock = Mutex()
    val pageCount = renderer.pageCount
    @Volatile private var closed = false

    /** Renders page [index] [width] pixels wide, turned by [rotation] degrees beyond the document's own rotation. */
    suspend fun render(index: Int, width: Int, rotation: Int): RenderedPage? = lock.withLock {
        if (closed) return@withLock null
        try { draw(index, width, rotation) } finally { if (closed) release() }
    }

    private suspend fun draw(index: Int, width: Int, rotation: Int): RenderedPage =
        withContext(Dispatchers.Default) {
            renderer.openPage(index).use { page ->
                val turned = rotation % 180 != 0
                val pageWidth = if (turned) page.height else page.width
                val pageHeight = if (turned) page.width else page.height
                val scale = width.toFloat() / pageWidth
                val height = (pageHeight * scale).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
                val matrix = Matrix().apply {
                    postScale(scale, scale)
                    postRotate(rotation.toFloat())
                    when (rotation) {
                        90 -> postTranslate(width.toFloat(), 0f)
                        180 -> postTranslate(width.toFloat(), height.toFloat())
                        270 -> postTranslate(0f, height.toFloat())
                    }
                }
                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                RenderedPage(bitmap, text(page), links(page, matrix))
            }
        }

    @SuppressLint("NewApi")
    private fun text(page: PdfRenderer.Page): String =
        if (contentApis()) runCatching { page.textContents.joinToString("\n") { it.text } }.getOrDefault("") else ""

    @SuppressLint("NewApi")
    private fun links(page: PdfRenderer.Page, matrix: Matrix): List<Pair<RectF, Int>> = if (!contentApis()) emptyList() else runCatching {
        page.gotoLinks.flatMap { link -> link.bounds.map { bounds -> RectF(bounds).also(matrix::mapRect) to link.destination.pageNumber + 1 } }
    }.getOrDefault(emptyList())

    /** A render in progress finishes first and then releases the document. */
    override fun close() {
        closed = true
        if (lock.tryLock()) try { release() } finally { lock.unlock() }
    }

    private var released = false
    private fun release() {
        if (released) return
        released = true
        runCatching { renderer.close() }
        runCatching { descriptor.close() }
    }

    companion object {
        /** Text and link extraction arrived in an SDK extension; older devices still render pages. */
        fun contentApis() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S) >= 13

        /** Throws when [file] is not a PDF the platform can open. */
        fun open(file: File): PdfDocument {
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            return try {
                PdfDocument(descriptor, PdfRenderer(descriptor))
            } catch (error: Exception) {
                descriptor.close()
                throw error
            }
        }
    }
}
