package com.audiobookshelf.android.ui

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.audiobookshelf.android.R
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File

private const val READER_ORIGIN = "https://reader.audiobookshelf.invalid/"
private data class ReaderLink(val label: String, val href: String)
private class ReaderEvents(private val receive: (JSONObject) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    @JavascriptInterface fun event(message: String) {
        if (message.length > 500_000) return
        val parsed = runCatching { JSONObject(message) }.getOrNull() ?: return
        main.post { receive(parsed) }
    }
}

/** Only bundled engine code is executable; book frames cannot execute scripts or reach the network. */
@SuppressLint("SetJavaScriptEnabled")
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublicationReaderScreen(route: Route.Reader, active: SessionState.Active, catalog: CatalogModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    val fileKey = if (route.supplementary) route.ino else PRIMARY_EBOOK
    val account = active.client.account
    var source by remember(route) { mutableStateOf<File?>(null) }
    var failure by remember(route) { mutableStateOf<String?>(null) }
    var ready by remember(route) { mutableStateOf(false) }
    var attempt by remember(route) { mutableIntStateOf(0) }
    var view by remember(route) { mutableStateOf<WebView?>(null) }
    var pageCount by remember(route) { mutableIntStateOf(0) }
    var pageNumber by remember(route) { mutableIntStateOf(1) }
    var shownProgress by remember(route) { mutableDoubleStateOf(0.0) }
    var contents by remember(route) { mutableStateOf<List<ReaderLink>>(emptyList()) }
    var results by remember(route) { mutableStateOf<List<ReaderLink>?>(null) }
    var showContents by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var unresolved by remember(route) { mutableStateOf<String?>(null) }
    val preferences = remember { com.audiobookshelf.android.reader.ReaderPreferences(context) }
    var readerSettings by remember { mutableStateOf(preferences.current()) }
    val textPublication = route.format !in setOf("cbz", "cbr")
    val scale = readerSettings.optInt("fontScale", 100).coerceIn(5, 300).toFloat()
    fun command(action: String, value: Any? = null) {
        val encoded = when (value) { is JSONObject -> value.toString(); null -> "null"; else -> JSONObject.quote(value.toString()) }
        view?.evaluateJavascript("window.readerCommand(${JSONObject.quote(action)},$encoded)", null)
    }
    fun applySettings() = command("settings", readerSettings)
    fun updateSetting(key: String, value: Any) {
        val next = JSONObject(readerSettings.toString()).put(key, value)
        try { preferences.update(next); readerSettings = next; command("settings", next) }
        catch (e: Exception) { failure = e.localizedMessage }
    }
    val activity = context as? com.audiobookshelf.android.MainActivity
    DisposableEffect(view, readerSettings) {
        val awake = readerSettings.optBoolean("keepScreenAwake", false)
        view?.keepScreenOn = awake
        activity?.readerVolumeNavigation = { key ->
            val mode = readerSettings.optString("navigateWithVolume", "none")
            if (mode !in setOf("enabled", "mirrored") || (graph.playback.state.value.playing && !readerSettings.optBoolean("navigateWithVolumeWhilePlaying", false))) false
            else {
                val forward = (key == android.view.KeyEvent.KEYCODE_VOLUME_DOWN) != (mode == "mirrored")
                command(if (forward) "next" else "previous"); true
            }
        }
        onDispose { view?.keepScreenOn = false; activity?.readerVolumeNavigation = null }
    }
    fun links(array: JSONArray?): List<ReaderLink> = (0 until (array?.length() ?: 0)).mapNotNull { i ->
        array?.optJSONObject(i)?.let { ReaderLink(it.optString("label"), it.optString("href")) }
    }
    LaunchedEffect(route, attempt) {
        failure = null; ready = false; source = null
        var staged: File? = null
        try {
            val open = resolveReaderFile(graph, active.client, route)
            val copy = withContext(Dispatchers.IO) {
                val file = File.createTempFile("publication-", ".bin", context.cacheDir).also { staged = it }
                try { ParcelFileDescriptor.AutoCloseInputStream(open()).use { input -> file.outputStream().use { input.copyTo(it) } }; file }
                catch (e: Exception) { file.delete(); throw e }
            }
            if (!route.supplementary) {
                val progress = if (route.downloadId == null && !route.localOnly) withTimeoutOrNull(4_000) { runCatching { catalog.freshUser() }.getOrNull() }
                    ?.mediaProgress?.firstOrNull { it.libraryItemId == route.itemId && it.episodeId == null } else null
                graph.reading.adoptRemote(account, route.itemId, fileKey, progress ?: catalog.progressFor(route.itemId))
            }
            source = copy
            staged = null
        } catch (e: Exception) {
            staged?.delete()
            if (e is kotlinx.coroutines.CancellationException) throw e
            graph.accounts.handle(e); failure = e.localizedMessage ?: context.getString(R.string.rd_document_not_opened)
        }
    }
    DisposableEffect(source) { val owned = source; onDispose { owned?.delete() } }
    DisposableEffect(view) { val owned = view; onDispose { owned?.stopLoading(); owned?.removeJavascriptInterface("NativeReader"); owned?.destroy() } }
    val changes by graph.reading.changes.collectAsState()
    val conflict = remember(changes) { graph.reading.entry(account, route.itemId, fileKey)?.takeIf { it.inConflict } }
    if (conflict != null) AlertDialog(onDismissRequest = {}, title = { Text(stringResource(R.string.rd_conflict_title)) },
        text = { Text(stringResource(R.string.rd_publication_conflict)) },
        confirmButton = { TextButton(onClick = {
            val target = conflict.conflictLocation ?: conflict.conflictPage?.toString()
            graph.reading.resolveConflict(account, route.itemId, fileKey, false)
            if (target != null) command("restore", target)
        }) { Text(stringResource(R.string.rd_use_saved_location)) } },
        dismissButton = { TextButton(onClick = { graph.reading.resolveConflict(account, route.itemId, fileKey, true); graph.readingSync.publishAll() }) { Text(stringResource(R.string.rd_keep_this_location)) } })
    if (unresolved != null) AlertDialog(onDismissRequest = {}, title = { Text(stringResource(R.string.rd_location_unresolved)) },
        text = { Text(stringResource(R.string.rd_location_preserved)) },
        confirmButton = { TextButton(onClick = { unresolved = null }) { Text(stringResource(R.string.rd_start_new_location)) } },
        dismissButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.rd_close_reader)) } })
    if (showContents || results != null) AlertDialog(onDismissRequest = { showContents = false; results = null },
        title = { Text(stringResource(if (results != null) R.string.rd_search_results else R.string.rd_contents)) },
        text = { LazyColumn { items(results ?: contents) { link -> TextButton(onClick = { command("go", link.href); showContents = false; results = null }) { Text(link.label) } } } },
        confirmButton = { TextButton(onClick = { showContents = false; results = null }) { Text(stringResource(R.string.rd_close_reader)) } })
    if (showSearch) AlertDialog(onDismissRequest = { showSearch = false }, title = { Text(stringResource(R.string.rd_search_book)) },
        text = { OutlinedTextField(query, { query = it }, label = { Text(stringResource(R.string.rd_search_book)) }) },
        confirmButton = { TextButton(onClick = { if (query.isNotBlank()) { command("search", query); showSearch = false } }) { Text(stringResource(R.string.rd_search_book)) } })
    if (showSettings) AlertDialog(onDismissRequest = { showSettings = false }, title = { Text(stringResource(R.string.rd_reading_settings)) },
        text = { LazyColumn {
            if (textPublication) item { Text(stringResource(R.string.rd_text_size) + ": ${scale.toInt()}%"); Slider(scale, { updateSetting("fontScale", it.toInt()) }, valueRange = 5f..300f) }
            item { Text(stringResource(R.string.rd_page_theme)); FlowRow { listOf("light", "dark", "black").forEach { theme -> FilterChip(selected = readerSettings.optString("theme", "light") == theme, onClick = { updateSetting("theme", theme) }, label = { Text(stringResource(when (theme) { "light" -> R.string.rd_light; "black" -> R.string.rd_black; else -> R.string.rd_dark })) }) } } }
            if (textPublication) item { Text(stringResource(R.string.rd_font)); FlowRow { listOf("serif", "sans-serif", "monospace").forEach { font -> TextButton(onClick = { updateSetting("font", font) }, modifier = Modifier.semantics { selected = readerSettings.optString("font", "serif") == font }) { Text(stringResource(when (font) { "serif" -> R.string.rd_font_serif; "sans-serif" -> R.string.rd_font_sans; else -> R.string.rd_font_mono })) } } } }
            if (textPublication) item { Text(stringResource(R.string.rd_line_spacing)); Slider(readerSettings.optInt("lineSpacing", 115).toFloat(), { updateSetting("lineSpacing", it.toInt()) }, valueRange = 100f..300f) }
            if (textPublication) item { Text(stringResource(R.string.rd_text_weight)); Slider(readerSettings.optInt("textStroke", 0).toFloat(), { updateSetting("textStroke", it.toInt()) }, valueRange = 0f..300f) }
            if (route.format == "epub") item { Text(stringResource(R.string.rd_spread)); FlowRow { listOf("auto", "none").forEach { spread -> TextButton(onClick = { updateSetting("spread", spread) }, modifier = Modifier.semantics { selected = readerSettings.optString("spread", "auto") == spread }) { Text(stringResource(if (spread == "auto") R.string.rd_spread_auto else R.string.rd_spread_single)) } } } }
            item { Row { Text(stringResource(R.string.rd_keep_awake), Modifier.weight(1f)); Switch(readerSettings.optBoolean("keepScreenAwake", false), { updateSetting("keepScreenAwake", it) }) } }
            item { Text(stringResource(R.string.rd_volume_navigation)); FlowRow { listOf("none", "enabled", "mirrored").forEach { mode -> TextButton(onClick = { updateSetting("navigateWithVolume", mode) }, modifier = Modifier.semantics { selected = readerSettings.optString("navigateWithVolume", "none") == mode }) { Text(stringResource(when (mode) { "none" -> R.string.rd_off; "mirrored" -> R.string.rd_mirrored; else -> R.string.rd_on })) } } } }
            item { Row { Text(stringResource(R.string.rd_volume_with_audio), Modifier.weight(1f)); Switch(readerSettings.optBoolean("navigateWithVolumeWhilePlaying", false), { updateSetting("navigateWithVolumeWhilePlaying", it) }) } }
        } }, confirmButton = { TextButton(onClick = { showSettings = false }) { Text(stringResource(R.string.rd_close_reader)) } })
    Scaffold(topBar = { TopAppBar(title = { Text(route.title, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }, navigationIcon = {
        TextButton(onClick = onClose, modifier = Modifier.testTag("reader-close")) { Text(stringResource(R.string.rd_close_reader)) }
    }) }) { padding -> Column(Modifier.padding(padding).navigationBarsPadding().fillMaxSize()) {
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            TextButton(onClick = { showContents = true }, enabled = ready) { Text(stringResource(R.string.rd_contents)) }
            if (route.format !in setOf("cbz", "cbr")) TextButton(onClick = { showSearch = true }, enabled = ready) { Text(stringResource(R.string.rd_search_book)) }
            TextButton(onClick = { showSettings = true }, enabled = ready) { Text(stringResource(R.string.rd_reading_settings)) }
        }
        failure?.let { Text(it, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error); TextButton(onClick = { attempt++ }) { Text(stringResource(R.string.action_retry)) } }
        val file = source
        if (file != null) key(file) { AndroidView(modifier = Modifier.weight(1f).fillMaxWidth().testTag("publication-content"), factory = {
            WebView(it).apply {
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false; settings.allowContentAccess = false
                settings.cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
                settings.domStorageEnabled = false; settings.setSupportZoom(true); settings.builtInZoomControls = true; settings.displayZoomControls = false
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest) =
                        !request.url.toString().startsWith(READER_ORIGIN) && !request.url.toString().startsWith("blob:")
                    override fun shouldInterceptRequest(v: WebView, request: WebResourceRequest): WebResourceResponse? {
                        val url = request.url.toString()
                        if (url.startsWith("blob:")) return null
                        if (!url.startsWith(READER_ORIGIN)) return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                        val path = request.url.path?.removePrefix("/") ?: ""
                        if (path.contains("..")) return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                        return runCatching {
                            if (path == "document") WebResourceResponse("application/octet-stream", null, file.inputStream())
                            else {
                                val type = when { path.endsWith(".js") -> "text/javascript"; path.endsWith(".wasm") -> "application/wasm"; else -> "text/html" }
                                WebResourceResponse(type, "UTF-8", context.assets.open("readers/$path"))
                            }
                        }.getOrElse { WebResourceResponse("text/plain", "UTF-8", 404, "Not found", emptyMap(), ByteArrayInputStream(ByteArray(0))) }
                    }
                }
                addJavascriptInterface(ReaderEvents { event -> when (event.optString("type")) {
                    "boot" -> command("open", JSONObject().put("format", route.format).put("settings", readerSettings).put("location", graph.reading.entry(account, route.itemId, fileKey)?.location ?: ""))
                    "ready" -> { ready = true; failure = null; pageCount = event.optInt("pages"); contents = links(event.optJSONArray("contents")); applySettings() }
                    "unresolved" -> unresolved = event.optString("location")
                    "results" -> results = links(event.optJSONArray("contents"))
                    "error" -> failure = event.optString("message")
                    "place" -> {
                        val shown = event.optString("location")
                        pageNumber = shown.toIntOrNull() ?: 1
                        shownProgress = event.optDouble("progress", 0.0).takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.0
                        if (event.optBoolean("moved") && unresolved == null && graph.reading.entry(account, route.itemId, fileKey)?.inConflict != true) scope.launch {
                            try { graph.reading.recordLocation(account, route.itemId, fileKey, !route.supplementary, shown, event.optDouble("progress", 0.0)); if (!route.supplementary) graph.readingSync.publishAll() }
                            catch (e: Exception) { failure = e.localizedMessage }
                        }
                    }
                } }, "NativeReader")
                view = this
                loadUrl(READER_ORIGIN + "index.html")
            }
        }) } else if (failure == null) CircularProgressIndicator(Modifier.padding(24.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            TextButton(onClick = { command("previous") }, enabled = ready, modifier = Modifier.testTag("reader-previous")) { Text(stringResource(R.string.rd_previous_page)) }
            if (ready) Text(if (pageCount > 0) stringResource(R.string.rd_page_of, pageNumber, pageCount) else java.text.NumberFormat.getPercentInstance().format(shownProgress))
            TextButton(onClick = { command("next") }, enabled = ready, modifier = Modifier.testTag("reader-next")) { Text(stringResource(R.string.rd_next_page)) }
        }
    } }
}
