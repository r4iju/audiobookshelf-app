package com.audiobookshelf.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.RssFeed
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.annotation.StringRes
import androidx.core.text.HtmlCompat
import com.audiobookshelf.android.R
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.Episode
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.PodcastDiscovery
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.text.DateFormat
import java.util.Date

private enum class EpisodeFilter(@StringRes val label: Int) { ALL(R.string.pod_filter_all), INCOMPLETE(R.string.pod_filter_incomplete), IN_PROGRESS(R.string.pod_filter_in_progress), FINISHED(R.string.finished) }

/** Opens playback for any source and calls [onOpened] once the player has it loaded. */
@Composable
fun rememberPlayLauncher(onOpened: () -> Unit): (PlaySource) -> Unit {
    val engine = LocalContext.current.graph.playback
    val state by engine.state.collectAsState()
    var waiting by remember { mutableStateOf<Pair<String, String?>?>(null) }
    LaunchedEffect(waiting, state.now, state.openError) {
        val target = waiting ?: return@LaunchedEffect
        if (state.now?.let { it.itemId == target.first && it.episodeId == target.second } == true) { waiting = null; onOpened() }
        else if (state.openError != null) waiting = null
    }
    return { source -> waiting = source.itemId to source.episodeId; engine.play(source) }
}

@Composable
fun PodcastDetail(item: LibraryItem, reload: () -> Unit, active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, actions: ItemActions, onEpisode: (String) -> Unit, onPlayer: () -> Unit) {
    val graph = LocalContext.current.graph
    val settings by graph.settings.settings.collectAsState()
    val requests by graph.podcastRequests.records.collectAsState()
    val engineState by graph.playback.state.collectAsState()
    val account = active.client.account
    var filter by remember { mutableStateOf(EpisodeFilter.ALL) }
    var feedSheet by remember { mutableStateOf(false) }
    val launch = rememberPlayLauncher(onPlayer)
    val pending = requests.filter { it.account == account && it.itemId == item.id && it.state == com.audiobookshelf.android.podcast.PodcastRequests.State.PENDING }
    val failures = requests.filter { it.account == account && it.itemId == item.id && it.state == com.audiobookshelf.android.podcast.PodcastRequests.State.FAILED }
    val cover = active.client.coverUrl(item.id).toString()

    LaunchedEffect(item) {
        runCatching { graph.podcastRequests.arrived(account, item.id, item.media.episodes.mapNotNull { it.enclosure?.url }) }
    }
    // The server announces failed downloads but not every arrival, so a pending queue refreshes the item.
    LaunchedEffect(pending.isNotEmpty()) {
        while (pending.isNotEmpty()) { delay(4_000); reload() }
    }
    LaunchedEffect(item.id) {
        graph.serverEvents.events.collect { event ->
            if (event.account == account && event.data?.optString("libraryItemId").let { it == item.id || it.isNullOrEmpty() } && event.name != "user_item_progress_updated") reload()
        }
    }

    val episodes = remember(item, settings.episodeDescending, filter, catalog.user) {
        val sorted = item.media.episodes.sortedBy { it.publishedAt ?: 0.0 }.let { if (settings.episodeDescending) it.reversed() else it }
        sorted.filter { episode ->
            val progress = catalog.progressFor(item.id, episode.id)
            when (filter) {
                EpisodeFilter.ALL -> true
                EpisodeFilter.INCOMPLETE -> progress?.isFinished != true
                EpisodeFilter.IN_PROGRESS -> progress != null && !progress.isFinished && progress.currentTime > 0
                EpisodeFilter.FINISHED -> progress?.isFinished == true
            }
        }
    }
    val canManage = catalog.user?.isAdmin == true && !item.media.metadata.feedUrl.isNullOrBlank()

    ItemDetail(item, cover, null, padding, actions, primary = {}, extra = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FeedButton(item, active, catalog)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.search_episodes), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f).semantics { heading() })
                if (canManage) TextButton(onClick = { feedSheet = true }, modifier = Modifier.testTag("feed-episodes")) {
                    Icon(Icons.Outlined.RssFeed, null, Modifier.size(18.dp)); Text(stringResource(R.string.pod_feed_episodes), Modifier.padding(start = 6.dp))
                }
                IconButton(onClick = { graph.settings.update { it.copy(episodeDescending = !it.episodeDescending) } }, modifier = Modifier.testTag("episode-sort")) {
                    Icon(Icons.AutoMirrored.Outlined.Sort, stringResource(if (settings.episodeDescending) R.string.pod_sort_newest_first else R.string.pod_sort_oldest_first))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                EpisodeFilter.entries.forEach { option ->
                    FilterChip(selected = filter == option, onClick = { filter = option }, label = { Text(stringResource(option.label)) }, modifier = Modifier.testTag("episode-filter-${option.name.lowercase()}"))
                }
            }
            if (pending.isNotEmpty()) Text(pluralStringResource(R.plurals.pod_episodes_queued, pending.size, pending.size, pending.joinToString { it.title }),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("queued-episodes"))
            failures.forEachIndexed { index, failure ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("feed-failure-$index")) {
                    Text(stringResource(R.string.pod_server_could_not_download, failure.title), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    TextButton(onClick = { runCatching { graph.podcastRequests.dismiss(failure.id) } }) { Text(stringResource(R.string.pod_dismiss)) }
                }
            }
            if (episodes.isEmpty()) Text(stringResource(if (item.media.episodes.isEmpty()) R.string.pod_no_episodes_yet else R.string.pod_no_episodes_match_filter),
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("episodes-empty"))
            engineState.openError?.takeIf { it.first.startsWith("${item.id}/") }?.let { Text(it.second, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("play-error")) }
        }
    }, more = {
        items(episodes, key = { it.id }) { episode ->
            val progress = catalog.progressFor(item.id, episode.id)
            EpisodeRow(episode, progress, onOpen = { onEpisode(episode.id) },
                onPlay = { launch(PlaySource.Stream(active.client, item.id, episode.id, cover, progress?.lastUpdate)) })
        }
    })

    if (feedSheet) FeedEpisodesSheet(active, item, onQueued = reload) { feedSheet = false }
}

@Composable
private fun EpisodeRow(episode: Episode, progress: MediaProgress?, onOpen: () -> Unit, onPlay: () -> Unit) {
    Column {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).clickable(role = Role.Button, onClickLabel = stringResource(R.string.pod_episode_details), onClick = onOpen).padding(vertical = 10.dp).testTag("episode-${episode.id}"),
                verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(episode.title.ifBlank { stringResource(R.string.pod_untitled_episode) }, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                val facts = listOfNotNull(episode.publishedAt?.let { DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(it.toLong())) },
                    episode.playableDuration.takeIf { it > 0 }?.let(::formatDuration),
                    progress?.takeIf { !it.isFinished && it.currentTime > 0 }?.let { stringResource(R.string.pod_time_left, formatDuration((it.duration - it.currentTime).coerceAtLeast(0.0))) })
                Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (progress != null && !progress.isFinished && progress.progress > 0) ProgressLine(progress.progress, Modifier.padding(top = 4.dp))
            }
            if (progress?.isFinished == true) Icon(Icons.Filled.CheckCircle, stringResource(R.string.finished), tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(horizontal = 4.dp).testTag("episode-done-${episode.id}"))
            IconButton(onClick = onPlay, modifier = Modifier.testTag("episode-play-${episode.id}")) {
                Icon(Icons.Filled.PlayCircle, stringResource(R.string.pod_play_named, episode.title), tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(32.dp))
            }
        }
        HorizontalDivider()
    }
}

@Composable
fun EpisodeScreen(item: LibraryItem, episodeId: String, active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onPlayer: () -> Unit) {
    val graph = LocalContext.current.graph
    val episode = item.media.episodes.firstOrNull { it.id == episodeId }
    if (episode == null) {
        Box(Modifier.padding(padding)) { MessageState(stringResource(R.string.pod_episode_not_available), stringResource(R.string.pod_episode_may_have_been_removed), tag = "episode-missing") }
        return
    }
    val progress = catalog.progressFor(item.id, episode.id)
    val cover = active.client.coverUrl(item.id).toString()
    val description = remember(episode.description) { episode.description?.let { HtmlCompat.fromHtml(it, HtmlCompat.FROM_HTML_MODE_COMPACT).toString().trim() }?.takeIf { it.isNotEmpty() } }
    Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).testTag("episode-detail"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Cover(cover, item.title, Modifier.widthIn(max = 120.dp).fillMaxWidth(0.3f), podcast = true)
            Column(Modifier.weight(1f)) {
                Text(item.title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text(episode.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                val facts = listOfNotNull(episode.publishedAt?.let { DateFormat.getDateInstance(DateFormat.LONG).format(Date(it.toLong())) }, episode.playableDuration.takeIf { it > 0 }?.let(::formatDuration))
                Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (progress != null && (progress.progress > 0 || progress.isFinished)) {
            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("item-progress")) {
                Text(if (progress.isFinished) stringResource(R.string.finished) else stringResource(R.string.pod_percent_listened, (progress.progress * 100).toInt()), style = MaterialTheme.typography.labelLarge)
                ProgressLine(if (progress.isFinished) 1.0 else progress.progress)
            }
        }
        PlayButton({ preferDownloaded(graph, active, item.id, episode.id, progress) ?: PlaySource.Stream(active.client, item.id, episode.id, cover, progress?.lastUpdate) }, item.id, episode.id, onOpened = onPlayer)
        DownloadButton(item, episode, active, catalog)
        ProgressActions(item.id, episode.id, active, catalog, tagPrefix = "episode", progressGeneration = item.progressGenerations[episode.id] ?: 0)
        AddToGroupButton(item.id, episode.id, active, catalog)
        description?.let { ExpandableText(it) }
    }
}

private class FeedEpisode(val key: String, val title: String, val url: String?, val raw: JsonElement)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FeedEpisodesSheet(active: SessionState.Active, item: LibraryItem, onQueued: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    var episodes by remember { mutableStateOf<List<FeedEpisode>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf(0) }
    var adding by remember { mutableStateOf(false) }
    val selected = remember { mutableStateListOf<String>() }
    val existing = remember(item) { item.media.episodes.mapNotNull { it.enclosure?.url }.toSet() }
    LaunchedEffect(attempt) {
        error = null
        try {
            val feed = active.client.podcastFeed(item.media.metadata.feedUrl.orEmpty())
            val list = (feed["podcast"]?.jsonObject?.get("episodes") as? JsonArray).orEmpty()
            val parsed = list.mapIndexed { index, element ->
                val value = element.jsonObject
                val url = (value["enclosure"] as? JsonObject)?.get("url")?.jsonPrimitive?.contentOrNull
                FeedEpisode(value["guid"]?.jsonPrimitive?.contentOrNull ?: "episode-$index", value["title"]?.jsonPrimitive?.contentOrNull ?: context.getString(R.string.pod_untitled_episode), url, element)
            }
            // A write from a worker thread can land before the sheet's dialog window first composes and be missed.
            withContext(Dispatchers.Main) { episodes = parsed }
        } catch (failure: Exception) { error = failure.localizedMessage ?: context.getString(R.string.pod_feed_could_not_open); graph.accounts.handle(failure) }
    }
    ModalBottomSheet(onDismissRequest = { if (!adding) onDismiss() }) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.pod_feed_episodes), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            val list = episodes
            when {
                error != null -> Column {
                    Text(error.orEmpty(), color = MaterialTheme.colorScheme.error)
                    TextButton(onClick = { attempt++ }) { Text(stringResource(R.string.pod_retry_feed)) }
                }
                list == null -> CircularProgressIndicator()
                list.isEmpty() -> Text(stringResource(R.string.pod_no_feed_episodes))
                else -> LazyColumn(Modifier.heightIn(max = 420.dp)) {
                    items(list, key = { it.key }) { episode ->
                        val onServer = episode.url in existing
                        val state = stringResource(if (onServer) R.string.pod_already_on_server else if (episode.key in selected) R.string.pod_selected else R.string.pod_not_selected)
                        val enabled = episode.url != null && !onServer && !adding
                        Row(
                            Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Checkbox) { if (episode.key in selected) selected.remove(episode.key) else selected.add(episode.key) }
                                .semantics { stateDescription = state }
                                .padding(vertical = 6.dp).testTag("feed-episode-${episode.key}"),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(checked = onServer || episode.key in selected, onCheckedChange = null, enabled = enabled)
                            Column(Modifier.padding(start = 8.dp)) {
                                Text(episode.title)
                                if (onServer) Text(stringResource(R.string.pod_already_on_server), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                else if (episode.url == null) Text(stringResource(R.string.pod_no_audio_enclosure), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            Button(
                onClick = {
                    val choices = list.orEmpty().filter { it.key in selected && it.url != null }
                    adding = true; error = null
                    scope.launch {
                        val account = active.client.account
                        try {
                            graph.podcastRequests.begin(account, item.id, choices.map { it.title to it.url!! })
                            active.client.downloadFeedEpisodes(item.id, choices.map { it.raw })
                            onQueued(); onDismiss()
                        } catch (failure: Exception) {
                            if (failure is ApiError.Http && failure.status in listOf(400, 401, 403, 404, 413)) runCatching { graph.podcastRequests.reject(account, item.id, choices.mapNotNull { it.url }) }
                            error = failure.localizedMessage?.let { context.getString(R.string.pod_not_queued, it) } ?: context.getString(R.string.pod_not_queued_try_again); graph.accounts.handle(failure)
                        } finally { adding = false }
                    }
                },
                enabled = selected.isNotEmpty() && !adding && list != null,
                modifier = Modifier.fillMaxWidth().testTag("queue-episodes"),
            ) { Text(stringResource(if (adding) R.string.pod_queueing_on_server else R.string.pod_add_selected_episodes)) }
        }
    }
}

/** Discover by name or RSS URL, preview the feed, then create the podcast in a library folder. */
@Composable
fun AddPodcastScreen(active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onCreated: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    val library = catalog.library
    val permitted = catalog.user?.isAdmin == true && library?.isPodcast == true
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<PodcastDiscovery>>(emptyList()) }
    var searched by remember { mutableStateOf(false) }
    var feedUrl by remember { mutableStateOf("") }
    var discovery by remember { mutableStateOf<PodcastDiscovery?>(null) }
    var feed by remember { mutableStateOf<JsonObject?>(null) }
    var title by remember { mutableStateOf("") }
    var author by remember { mutableStateOf("") }
    var folderId by remember { mutableStateOf(library?.folders?.firstOrNull()?.id) }
    var autoDownload by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun run(block: suspend () -> Unit) {
        busy = true; error = null
        scope.launch { try { block() } catch (failure: Exception) { error = failure.localizedMessage ?: context.getString(R.string.pod_something_went_wrong); graph.accounts.handle(failure) } finally { busy = false } }
    }
    fun preview(url: String, chosen: PodcastDiscovery?) = run {
        val value = active.client.podcastFeed(url)
        val metadata = value["podcast"]?.jsonObject?.get("metadata") as? JsonObject
        feedUrl = url; discovery = chosen; feed = value
        title = chosen?.title ?: metadata?.get("title")?.jsonPrimitive?.contentOrNull.orEmpty()
        author = chosen?.artistName ?: metadata?.get("author")?.jsonPrimitive?.contentOrNull.orEmpty()
    }

    if (!permitted) {
        Box(Modifier.padding(padding)) { MessageState(stringResource(R.string.pod_adding_not_available), stringResource(R.string.pod_adding_needs_permission), tag = "add-podcast-denied") }
        return
    }
    Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val loaded = feed
        if (loaded == null) {
            OutlinedTextField(query, { query = it }, label = { Text(stringResource(R.string.pod_search_podcasts)) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("podcast-query"),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { if (query.isNotBlank()) run { results = active.client.discoverPodcasts(query.trim()); searched = true } }))
            Button(onClick = { run { results = active.client.discoverPodcasts(query.trim()); searched = true } }, enabled = !busy && query.isNotBlank(), modifier = Modifier.testTag("podcast-search")) { Text(stringResource(R.string.tab_search)) }
            if (searched && results.isEmpty()) Text(stringResource(R.string.pod_no_podcasts_found), color = MaterialTheme.colorScheme.onSurfaceVariant)
            results.forEach { result ->
                Row(Modifier.fillMaxWidth().clickable(enabled = !busy && result.feedUrl != null, role = Role.Button) { preview(result.feedUrl!!, result) }
                    .padding(vertical = 8.dp).testTag("podcast-discovery-${result.id}"), verticalAlignment = Alignment.CenterVertically) {
                    Cover(result.cover, result.title, Modifier.size(56.dp), podcast = true)
                    Column(Modifier.padding(start = 12.dp)) {
                        Text(result.title, style = MaterialTheme.typography.bodyLarge)
                        Text(listOfNotNull(result.artistName, result.genres.firstOrNull()).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            HorizontalDivider()
            OutlinedTextField(feedUrl, { feedUrl = it }, label = { Text(stringResource(R.string.pod_or_rss_feed_url)) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("podcast-feed-url"),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
            OutlinedButton(onClick = {
                val url = feedUrl.trim()
                if (!url.startsWith("http://") && !url.startsWith("https://")) error = context.getString(R.string.pod_enter_complete_feed_url) else preview(url, null)
            }, enabled = !busy && feedUrl.isNotBlank(), modifier = Modifier.testTag("preview-feed")) { Text(stringResource(R.string.pod_preview_feed)) }
        } else {
            OutlinedTextField(title, { title = it }, label = { Text(stringResource(R.string.pod_title)) }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("podcast-title"))
            OutlinedTextField(author, { author = it }, label = { Text(stringResource(R.string.pod_author)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Text(stringResource(R.string.pod_folder), style = MaterialTheme.typography.titleSmall)
            library.folders.forEach { folder ->
                Row(Modifier.fillMaxWidth().clickable(role = Role.RadioButton) { folderId = folder.id }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = folderId == folder.id, onClick = null)
                    Text(folder.fullPath, Modifier.padding(start = 8.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.pod_auto_download_episodes), Modifier.weight(1f))
                Switch(autoDownload, { autoDownload = it })
            }
            val folder = library.folders.firstOrNull { it.id == folderId }
            val safeName = title.replace(Regex("[/\\\\:?*\"<>|\\p{Cntrl}]"), "_").trim()
            Button(onClick = {
                run {
                    val metadata = loaded["podcast"]?.jsonObject?.get("metadata") as? JsonObject
                    val chosen = discovery
                    active.client.createPodcast(buildJsonObject {
                        put("libraryId", library.id); put("folderId", folder!!.id); put("path", folder.fullPath.trimEnd('/') + "/" + safeName)
                        putJsonObject("media") {
                            putJsonObject("metadata") {
                                put("title", title.trim()); put("author", author.trim())
                                put("description", chosen?.description ?: metadata?.get("descriptionPlain")?.jsonPrimitive?.contentOrNull.orEmpty())
                                put("feedUrl", chosen?.feedUrl ?: metadata?.get("feedUrl")?.jsonPrimitive?.contentOrNull ?: feedUrl)
                                put("imageUrl", chosen?.cover ?: metadata?.get("image")?.jsonPrimitive?.contentOrNull.orEmpty())
                                putJsonArray("genres") { (chosen?.genres ?: (metadata?.get("categories") as? JsonArray)?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty()).forEach { add(JsonPrimitive(it)) } }
                                put("itunesId", chosen?.id?.toString().orEmpty())
                            }
                            put("autoDownloadEpisodes", autoDownload)
                        }
                    })
                    catalog.reload()
                    onCreated()
                }
            }, enabled = !busy && folder != null && safeName.isNotEmpty() && safeName != "." && safeName != "..", modifier = Modifier.fillMaxWidth().testTag("create-podcast")) { Text(stringResource(R.string.pod_create_podcast)) }
            TextButton(onClick = { feed = null }) { Text(stringResource(R.string.pod_choose_different_feed)) }
        }
        if (busy) CircularProgressIndicator()
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("add-podcast-error")) }
    }
}
