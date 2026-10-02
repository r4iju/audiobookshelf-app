package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.navigationBarsPadding
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.RotateRight
import androidx.compose.material.icons.outlined.ViewDay
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.AppGraph
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.download.DownloadStore
import com.audiobookshelf.android.download.Downloads
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.reader.PdfDocument
import com.audiobookshelf.android.reader.RenderedPage
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.math.abs

/** Reading-position key of an item's primary ebook, which the server tracks per item rather than per file. */
const val PRIMARY_EBOOK = "primary"

private class Opened(val document: PdfDocument, val startPage: Int)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PdfReaderScreen(route: Route.Reader, active: SessionState.Active, catalog: CatalogModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val account = active.client.account
    val fileKey = if (route.supplementary) route.ino else PRIMARY_EBOOK
    val settings by graph.settings.settings.collectAsState()
    val scope = rememberCoroutineScope()
    var attempt by remember { mutableIntStateOf(0) }
    var opened by remember { mutableStateOf<Opened?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var page by remember { mutableIntStateOf(1) }
    var rotation by remember { mutableIntStateOf(0) }
    var saveError by remember { mutableStateOf(if (graph.reading.writable) null else context.getString(R.string.rd_positions_not_restored)) }

    LaunchedEffect(attempt) {
        error = null
        opened = null
        try {
            val file = resolve(graph, active.client, route)
            val document = withContext(Dispatchers.IO) {
                runCatching { PdfDocument.open(file()) }.getOrElse { throw IOException(context.getString(R.string.rd_not_a_pdf)) }
            }
            if (!route.supplementary) {
                // A fresh server position is worth a short wait; offline, the last known one is used.
                val progress = if (route.downloadId == null) withTimeoutOrNull(4_000) { runCatching { catalog.freshUser() }.getOrNull() }
                    ?.mediaProgress?.firstOrNull { it.libraryItemId == route.itemId && it.episodeId == null }
                    else null
                runCatching { graph.reading.adoptRemote(account, route.itemId, fileKey, progress ?: catalog.progressFor(route.itemId)) }
            }
            val start = graph.reading.entry(account, route.itemId, fileKey)?.page?.coerceIn(1, document.pageCount.coerceAtLeast(1)) ?: 1
            page = start
            opened = Opened(document, start)
        } catch (failure: Exception) {
            if (failure is kotlinx.coroutines.CancellationException) throw failure
            graph.accounts.handle(failure)
            graph.diagnostics.record(com.audiobookshelf.android.data.Diagnostics.Area.MEDIA, "PDF \"${route.title}\" could not be opened", failure)
            error = when (failure) {
                is ApiError -> failure.message
                else -> failure.message ?: context.getString(R.string.rd_document_not_opened)
            }
        }
    }
    DisposableEffect(opened) {
        val current = opened
        onDispose { current?.document?.close() }
    }

    val document = opened?.document
    LaunchedEffect(document) {
        val current = document ?: return@LaunchedEffect
        snapshotFlow { page }.distinctUntilChanged().collect { shown ->
            if (graph.reading.entry(account, route.itemId, fileKey)?.page == shown) return@collect
            try {
                graph.reading.record(account, route.itemId, fileKey, primary = !route.supplementary, page = shown, pages = current.pageCount)
                if (!route.supplementary) graph.readingSync.publishAll()
            } catch (failure: Exception) {
                saveError = storeFailure(context, graph, failure) ?: context.getString(R.string.rd_page_not_saved)
            }
        }
    }

    val changes by graph.reading.changes.collectAsState()
    val conflictEntry = remember(changes) { if (route.supplementary) null else graph.reading.entry(account, route.itemId, fileKey)?.takeIf { it.inConflict } }
    if (document != null && conflictEntry != null) {
        val conflict = conflictEntry.conflictPage
        fun resolve(keepLocal: Boolean) {
            try {
                graph.reading.resolveConflict(account, route.itemId, fileKey, keepLocal)
                if (keepLocal) graph.readingSync.publishAll() else if (conflict != null) page = conflict.coerceIn(1, document.pageCount)
            } catch (failure: Exception) {
                saveError = storeFailure(context, graph, failure) ?: context.getString(R.string.rd_choice_not_saved)
            }
        }
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.rd_conflict_title)) },
            text = {
                Text(if (conflict != null) stringResource(R.string.rd_conflict_page, conflict, page)
                    else stringResource(R.string.rd_conflict_location, page))
            },
            confirmButton = {
                TextButton(onClick = { resolve(keepLocal = false) }, modifier = Modifier.testTag("reading-conflict-remote")) {
                    Text(if (conflict != null) stringResource(R.string.rd_go_to_page_number, conflict) else stringResource(R.string.rd_keep_other_position))
                }
            },
            dismissButton = { TextButton(onClick = { resolve(keepLocal = true) }, modifier = Modifier.testTag("reading-conflict-local")) { Text(stringResource(R.string.rd_stay_on_page, page)) } },
            modifier = Modifier.testTag("reading-conflict"),
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(route.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onClose, modifier = Modifier.testTag("reader-close")) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rd_close_reader)) } },
                actions = {
                    IconButton(onClick = { rotation = (rotation + 90) % 360 }, modifier = Modifier.testTag("pdf-rotate")) { Icon(Icons.Outlined.RotateRight, stringResource(R.string.rd_rotate_pages)) }
                    val continuous = stringResource(R.string.rd_continuous_scrolling)
                    IconToggleButton(
                        checked = settings.pdfContinuous,
                        onCheckedChange = { on -> graph.settings.update { it.copy(pdfContinuous = on) } },
                        modifier = Modifier.testTag("pdf-continuous").semantics { contentDescription = continuous },
                    ) { Icon(Icons.Outlined.ViewDay, null) }
                },
            )
        },
        bottomBar = {
            Column(Modifier.navigationBarsPadding()) {
                if (document != null) PageControls(page, document.pageCount, onPage = { page = it })
                LocalBottomAccessory.current()
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).background(MaterialTheme.colorScheme.surfaceContainer)) {
            when {
                error != null -> MessageState(stringResource(R.string.rd_document_error_title), error, tag = "pdf-error", action = stringResource(R.string.rd_try_again), actionTag = "pdf-retry", onAction = { attempt++ })
                document == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                settings.pdfContinuous -> ContinuousPages(document, page, rotation, onPage = { page = it })
                else -> SinglePage(document, page, rotation, onPage = { page = it.coerceIn(1, document.pageCount) })
            }
            saveError?.let {
                Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth()) {
                    Text(it, Modifier.padding(12.dp).testTag("reading-save-error"), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun PageControls(page: Int, count: Int, onPage: (Int) -> Unit) {
    Surface(tonalElevation = 2.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
            if (count > 2) {
                val goToPage = stringResource(R.string.rd_go_to_page)
                var dragging by remember { mutableFloatStateOf(-1f) }
                Slider(
                    value = if (dragging >= 0) dragging else page.toFloat(),
                    onValueChange = { dragging = it },
                    onValueChangeFinished = { onPage(dragging.toInt().coerceIn(1, count)); dragging = -1f },
                    valueRange = 1f..count.toFloat(),
                    modifier = Modifier.height(32.dp).semantics { contentDescription = goToPage },
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                IconButton(onClick = { onPage(page - 1) }, enabled = page > 1, modifier = Modifier.testTag("pdf-previous")) { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, stringResource(R.string.rd_previous_page)) }
                Text(stringResource(R.string.rd_page_of, page, count), style = MaterialTheme.typography.labelLarge, modifier = Modifier.testTag("pdf-page"))
                IconButton(onClick = { onPage(page + 1) }, enabled = page < count, modifier = Modifier.testTag("pdf-next")) { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, stringResource(R.string.rd_next_page)) }
            }
        }
    }
}

@Composable
private fun rememberPage(document: PdfDocument, index: Int, width: Int, rotation: Int): RenderedPage? =
    produceState<RenderedPage?>(null, document, index, width, rotation) { value = document.render(index, width, rotation) }.value

@Composable
private fun SinglePage(document: PdfDocument, page: Int, rotation: Int, onPage: (Int) -> Unit) {
    var scale by remember(page, rotation) { mutableFloatStateOf(1f) }
    var offset by remember(page, rotation) { mutableStateOf(Offset.Zero) }
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val width = constraints.maxWidth.coerceIn(1, 2_000)
        val rendered = rememberPage(document, page - 1, width, rotation)
        val pageOf = stringResource(R.string.rd_page_of, page, document.pageCount)
        Box(
            Modifier.fillMaxSize().testTag("pdf-document").semantics {
                contentDescription = pageOf
                stateDescription = rendered?.text.orEmpty()
            },
            contentAlignment = Alignment.Center,
        ) {
            if (rendered == null) CircularProgressIndicator()
            else Image(
                rendered.bitmap.asImageBitmap(), null,
                Modifier.fillMaxWidth()
                    .aspectRatio(rendered.bitmap.width.toFloat() / rendered.bitmap.height)
                    .testTag("pdf-page-image")
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y }
                    .background(Color.White)
                    .pointerInput(rendered) {
                        detectTapGestures(
                            onDoubleTap = { if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f },
                            onTap = { at ->
                                val factor = rendered.bitmap.width / size.width.toFloat()
                                rendered.links.firstOrNull { (area, _) -> area.contains(at.x * factor, at.y * factor) }?.let { onPage(it.second) }
                            },
                        )
                    }
                    .pointerInput(page) {
                        awaitEachGesture {
                            awaitFirstDown(requireUnconsumed = false)
                            var swipe = 0f
                            do {
                                val event = awaitPointerEvent()
                                val zoom = event.calculateZoom()
                                val pan = event.calculatePan()
                                if (zoom != 1f || scale > 1f) {
                                    scale = (scale * zoom).coerceIn(1f, 5f)
                                    offset = if (scale == 1f) Offset.Zero else offset + pan
                                    event.changes.forEach { it.consume() }
                                } else swipe += pan.x
                            } while (event.changes.any { it.pressed })
                            if (scale == 1f && abs(swipe) > 120f) onPage(if (swipe < 0) page + 1 else page - 1)
                        }
                    },
            )
        }
    }
}

@Composable
private fun ContinuousPages(document: PdfDocument, page: Int, rotation: Int, onPage: (Int) -> Unit) {
    val list = rememberLazyListState(initialFirstVisibleItemIndex = page - 1)
    LaunchedEffect(list) {
        snapshotFlow { list.firstVisibleItemIndex + 1 }.distinctUntilChanged().collect { if (it != page) onPage(it) }
    }
    LaunchedEffect(page) { if (list.firstVisibleItemIndex + 1 != page) list.animateScrollToItem(page - 1) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = constraints.maxWidth.coerceIn(1, 2_000)
        var currentText by remember { mutableStateOf("") }
        val pageOf = stringResource(R.string.rd_page_of, page, document.pageCount)
        LazyColumn(
            state = list,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxSize().testTag("pdf-document").semantics {
                contentDescription = pageOf
                stateDescription = currentText
            },
        ) {
            items(document.pageCount) { index ->
                val rendered = rememberPage(document, index, width, rotation)
                if (index == page - 1) LaunchedEffect(rendered) { currentText = rendered?.text.orEmpty() }
                if (rendered == null) Box(Modifier.fillMaxWidth().aspectRatio(0.77f).background(Color.White))
                else Image(rendered.bitmap.asImageBitmap(), stringResource(R.string.rd_page_number, index + 1), Modifier.fillMaxWidth()
                    .aspectRatio(rendered.bitmap.width.toFloat() / rendered.bitmap.height).background(Color.White).testTag("pdf-page-image-${index + 1}"))
            }
        }
    }
}

/** A failure's message; the reading store's refusal to overwrite positions it could not read is shown in the reader's language. */
private fun storeFailure(context: android.content.Context, graph: AppGraph, failure: Exception): String? =
    if (failure is IllegalStateException && !graph.reading.writable) context.getString(R.string.rd_positions_not_overwritten) else failure.message

/** The downloaded copy when there is one, otherwise the server's file streamed to the cache. */
private suspend fun resolve(graph: AppGraph, client: ApiClient, route: Route.Reader): () -> ParcelFileDescriptor {
    val records = graph.downloads.records.value
    val local = records.firstOrNull { it.id == route.downloadId }
        ?: records.firstOrNull { it.account == client.account && it.itemId == route.itemId && it.episodeId == null && it.state == DownloadStore.State.COMPLETE && it.ebook?.ebookFileId == route.ino }
    if (local != null && local.ebook != null) when (val opened = graph.downloads.openPart(local, local.ebook!!)) {
        is Downloads.Opened.Readable -> return opened.open
        is Downloads.Opened.FolderLost -> if (route.downloadId != null) throw IOException(graph.context.getString(R.string.rd_download_folder_lost, opened.name))
        Downloads.Opened.Missing -> Unit
    }
    if (route.downloadId != null) throw IOException(graph.context.getString(R.string.rd_downloaded_document_missing))
    return withContext(Dispatchers.IO) {
        val name = MessageDigest.getInstance("SHA-256").digest("${client.account.server}\n${route.itemId}\n${route.ino}".toByteArray()).take(12).joinToString("") { "%02x".format(it) }
        val directory = File(graph.context.cacheDir, "reader").apply { mkdirs() }
        val target = File(directory, "$name.pdf")
        val staging = File(directory, "$name.part")
        val url = client.mediaUrl("/api/items/${route.itemId}/file/${route.ino}")
        var token = client.bearer()
        for (round in 0..1) {
            val request = okhttp3.Request.Builder().url(url).header("Authorization", "Bearer $token").build()
            graph.http.newCall(request).await().use { response ->
                if (response.code == 401 && round == 0) { token = client.bearerAfterRejection(token); return@use }
                if (response.code == 401) throw ApiError.SignInRequired(client.account, token)
                if (!response.isSuccessful) throw ApiError.Http(response.code)
                val body = response.body ?: throw IOException("Empty response")
                staging.outputStream().use { output -> body.byteStream().use { it.copyTo(output) } }
                target.delete()
                if (!staging.renameTo(target)) throw IOException(graph.context.getString(R.string.rd_document_not_stored))
                return@withContext { ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY) }
            }
        }
        throw ApiError.SignInRequired(client.account, token)
    }
}

/** Opens the item's PDF and its supplementary PDFs. Other ebook formats wait for their native readers. */
@Composable
fun ReadButtons(item: com.audiobookshelf.core.LibraryItem, onRead: (Route) -> Unit) {
    val ebook = item.media.ebookFile
    val supplementaryPdf = stringResource(R.string.rd_supplementary_pdf)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (ebook != null && ebook.format == "pdf") {
            androidx.compose.material3.OutlinedButton(onClick = { onRead(Route.Reader(item.id, ebook.ino, supplementary = false, title = item.title)) }, modifier = Modifier.fillMaxWidth().testTag("read-ebook")) {
                Icon(Icons.AutoMirrored.Outlined.MenuBook, null); Text(stringResource(R.string.action_read, "PDF"), Modifier.padding(start = 6.dp))
            }
        } else if (ebook != null) {
            Text(ebook.format?.let { stringResource(R.string.rd_format_not_available, it.uppercase()) } ?: stringResource(R.string.rd_ebook_not_available),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("ebook-unsupported"))
        }
        item.libraryFiles.filter { it.isSupplementary == true && it.format == "pdf" }.forEach { file ->
            val name = file.metadata?.filename ?: supplementaryPdf
            androidx.compose.material3.TextButton(onClick = { onRead(Route.Reader(item.id, file.ino, supplementary = true, title = name)) }, modifier = Modifier.testTag("read-file-${file.ino}")) {
                Text(stringResource(R.string.action_read, name))
            }
        }
    }
}
