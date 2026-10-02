package com.audiobookshelf.android.playback

import android.content.Context
import androidx.annotation.PluralsRes
import com.audiobookshelf.android.R
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionError
import com.audiobookshelf.android.data.SeriesOrder
import com.audiobookshelf.android.download.DownloadStore
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.CarBrowsing
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.NamedRef
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.guava.future

/**
 * Browse tree for Android Auto and other media browsers, laid out as in the existing app. IDs:
 * `root`, `continue`, `recent`, `recent/<lib>`, `shelf/<lib>/<shelf>`, `libraries`, `library/<lib>`,
 * `authors/<lib>[~<letters>]`, `author/<lib>/<id>`, `authorseries/<lib>/<author>/<series>`,
 * `serieslist/<lib>[~<letters>]`, `series/<lib>/<id>`, `collections/<lib>`, `collection/<id>`,
 * `discovery/<lib>`, `podcast/<item>`, `downloads`, and the playable `item/<id>`,
 * `episode/<item>/<episode>` and `download/<record>`.
 */
class BrowseTree(private val context: Context) {
    private val graph get() = context.graph
    private val client: ApiClient? get() = graph.accounts.activeClient
    private var lastSearch: Pair<String, List<MediaItem>>? = null

    fun root(params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> {
        val extras = Bundle().apply {
            putBoolean("android.media.browse.SEARCH_SUPPORTED", true)
            putInt("android.media.browse.CONTENT_STYLE_BROWSABLE_HINT", 1)
            putInt("android.media.browse.CONTENT_STYLE_PLAYABLE_HINT", 1)
        }
        return Futures.immediateFuture(LibraryResult.ofItem(folder(ROOT, "Audiobookshelf"), LibraryParams.Builder().setExtras(extras).build()))
    }

    fun children(parentId: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
        graph.scope.future {
            if (parentId == DOWNLOADS) return@future LibraryResult.ofItemList(downloads(), params)
            val api = client
            if (api == null) {
                return@future if (parentId == ROOT) LibraryResult.ofItemList(listOf(folder(DOWNLOADS, context.getString(R.string.tab_downloads))), params)
                else LibraryResult.ofError(SessionError.ERROR_SESSION_AUTHENTICATION_EXPIRED)
            }
            try {
                LibraryResult.ofItemList(listing(api, parentId, page, pageSize), params)
            } catch (failure: Exception) {
                graph.accounts.handle(failure)
                // Without the server the car still offers what is on the phone.
                if (parentId == ROOT) LibraryResult.ofItemList(listOf(folder(DOWNLOADS, context.getString(R.string.tab_downloads))), params)
                else LibraryResult.ofError(SessionError.ERROR_IO)
            }
        }

    private suspend fun listing(api: ApiClient, parentId: String, page: Int, pageSize: Int): List<MediaItem> {
        val parts = parentId.substringBefore('~').split('/')
        val letters = parentId.substringAfter('~', "")
        val settings = graph.settings.current
        return when (parentId) {
            ROOT -> {
                val libraries = api.libraries()
                val inProgress = libraries.any { library -> continuing(api, library.id).isNotEmpty() }
                listOfNotNull(
                    folder(CONTINUE, context.getString(R.string.auto_continue)).takeIf { inProgress },
                    folder(RECENT, context.getString(R.string.auto_recent)),
                    folder(LIBRARIES, context.getString(R.string.auto_libraries)),
                    folder(DOWNLOADS, context.getString(R.string.tab_downloads)),
                )
            }
            CONTINUE -> {
                val progress = progress(api)
                api.libraries().flatMap { continuing(api, it.id) }.distinctBy { it.id + it.recentEpisode?.id }.map { playable(it, api, progress) }
            }
            RECENT -> api.libraries().map { folder("$RECENT/${it.id}", it.name) }
            LIBRARIES -> api.libraries().map { folder("library/${it.id}", it.name) }
            else -> when (parts[0]) {
                "recent" -> api.personalized(parts[1]).filter { it.id in RECENT_SHELVES && it.entities.isNotEmpty() }
                    .map { folder("shelf/${parts[1]}/${it.id}", it.label) }
                "shelf" -> {
                    val shelf = api.personalized(parts[1]).firstOrNull { it.id == parts[2] } ?: return emptyList()
                    when (shelf.type) {
                        "series" -> shelf.entities.map { AbsJson.decodeFromJsonElement(NamedRef.serializer(), it) }.map { folder("series/${parts[1]}/${it.id}", it.name) }
                        "authors" -> shelf.entities.map { AbsJson.decodeFromJsonElement(NamedRef.serializer(), it) }.map { folder("author/${parts[1]}/${it.id}", it.name) }
                        else -> progress(api).let { progress -> shelf.items().map { playable(it, api, progress) } }
                    }
                }
                "library" -> {
                    val library = api.libraries().firstOrNull { it.id == parts[1] } ?: return emptyList()
                    if (library.isPodcast) {
                        api.items(library.id, 0, limit = 100).results.map { folder("podcast/${it.id}", it.title, it.author, api.coverUrl(it.id).toString()) }
                    } else listOfNotNull(
                        folder("authors/${library.id}", context.getString(R.string.search_authors)),
                        folder("serieslist/${library.id}", context.getString(R.string.search_series)),
                        folder("collections/${library.id}", context.getString(R.string.title_collections)),
                        folder("discovery/${library.id}", context.getString(R.string.auto_discovery)).takeIf { discovery(api, library.id).isNotEmpty() },
                    )
                }
                "authors" -> {
                    val authors = api.authors(parts[1]).filter { (it.numBooks ?: 0) > 0 && CarBrowsing.inGroup(it.name, letters) }.sortedBy { it.name.lowercase() }
                    grouped(authors.map { it.name }, settings.androidAutoBrowseLimitForGrouping, letters, "authors/${parts[1]}", R.plurals.auto_authors_count)
                        ?: authors.map { folder("author/${parts[1]}/${it.id}", it.name) }
                }
                "serieslist" -> {
                    val series = api.series(parts[1]).filter { CarBrowsing.inGroup(it.name, letters) }.sortedBy { it.name.lowercase() }
                    grouped(series.map { it.name }, settings.androidAutoBrowseLimitForGrouping, letters, "serieslist/${parts[1]}", R.plurals.auto_series_count)
                        ?: series.map { folder("series/${parts[1]}/${it.id}", it.name) }
                }
                "series", "authorseries" -> {
                    val seriesId = parts.last()
                    val books = api.items(parts[1], 0, filter = ApiClient.filter("series", seriesId), limit = 1000).results
                        .map { item -> item to item.media.metadata.series.firstOrNull { it.id == seriesId }?.sequence }
                        .sortedWith(compareBy(CarBrowsing.bySequence) { it.second })
                        .let { if (settings.androidAutoBrowseSeriesSequenceOrder == SeriesOrder.DESC) it.reversed() else it }
                    val progress = progress(api)
                    books.map { (item, sequence) -> playable(item, api, progress, prefix = sequence?.let { "$it. " }.orEmpty()) }
                }
                "author" -> {
                    val progress = progress(api)
                    api.items(parts[1], 0, filter = ApiClient.filter("authors", parts[2]), limit = 1000, collapseSeries = true).results.map { item ->
                        item.collapsedSeries?.let { folder("authorseries/${parts[1]}/${parts[2]}/${it.id}", it.name, context.resources.getQuantityString(R.plurals.lib_books_count, it.numBooks, it.numBooks)) } ?: playable(item, api, progress)
                    }
                }
                "collections" -> api.collections(parts[1]).map { folder("collection/${it.id}", it.name) }
                "collection" -> progress(api).let { progress -> api.collection(parts[1]).books.map { playable(it, api, progress) } }
                "discovery" -> progress(api).let { progress -> discovery(api, parts[1]).map { playable(it, api, progress) } }
                "podcast" -> {
                    val podcast = api.item(parts[1])
                    val progress = progress(api)
                    podcast.media.episodes.sortedByDescending { it.publishedAt ?: 0.0 }.map { playable(podcast.copy(recentEpisode = it), api, progress) }
                }
                else -> emptyList()
            }
        }
    }

    private fun grouped(names: List<String>, limit: Int, letters: String, base: String, @PluralsRes counted: Int): List<MediaItem>? =
        CarBrowsing.groups(names, limit, letters)?.map { folder("$base~${it.prefix}", it.prefix, context.resources.getQuantityString(counted, it.count, it.count)) }

    private suspend fun continuing(api: ApiClient, libraryId: String) =
        api.personalized(libraryId).filter { it.id == "continue-listening" }.flatMap { it.items() }

    private suspend fun discovery(api: ApiClient, libraryId: String) = api.personalized(libraryId).firstOrNull { it.id == "discover" }?.items().orEmpty()

    private suspend fun progress(api: ApiClient): Map<Pair<String, String?>, MediaProgress> =
        runCatching { api.me().mediaProgress }.getOrDefault(emptyList()).associateBy { it.libraryItemId to it.episodeId }

    private fun usable(record: DownloadStore.Record) = record.state == DownloadStore.State.COMPLETE && record.audio.isNotEmpty() &&
        !graph.downloads.folderLost(record) && !graph.downloads.missing(record)

    private fun downloads(): List<MediaItem> {
        val account = client?.account ?: return emptyList()
        return graph.downloads.records.value.filter { it.account == account }.filter(::usable).map { record ->
            MediaItem.Builder().setMediaId("download/${record.id}")
                .setMediaMetadata(
                    MediaMetadata.Builder().setTitle(record.title).setArtist(record.author).setIsBrowsable(false).setIsPlayable(true)
                        .setMediaType(if (record.episodeId != null) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK)
                        .setExtras(Bundle().apply { putLong(EXTRA_DOWNLOAD_STATUS, STATUS_DOWNLOADED) }).build(),
                )
                .build()
        }
    }

    fun item(mediaId: String): ListenableFuture<LibraryResult<MediaItem>> =
        Futures.immediateFuture(LibraryResult.ofItem(MediaItem.Builder().setMediaId(mediaId).build(), null))

    fun search(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> =
        graph.scope.future {
            val results = runSearch(query)
            lastSearch = query to results
            session.notifySearchResultChanged(browser, query, results.size, params)
            LibraryResult.ofVoid()
        }

    fun searchResult(query: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
        graph.scope.future {
            val results = lastSearch?.takeIf { it.first == query }?.second ?: runSearch(query)
            LibraryResult.ofItemList(results.drop(page * pageSize).take(pageSize), params)
        }

    private suspend fun runSearch(query: String): List<MediaItem> {
        val api = client ?: return emptyList()
        val libraries = runCatching { api.libraries() }.getOrDefault(emptyList())
        val progress = progress(api)
        return libraries.flatMap { library ->
            runCatching { api.search(library.id, query) }.getOrNull()?.let { result ->
                (result.book + result.podcast).map { playable(it.libraryItem, api, progress) } +
                    result.series.map { folder("series/${library.id}/${it.series.id}", it.series.name) } +
                    result.authors.map { folder("author/${library.id}/${it.id}", it.name) }
            }.orEmpty()
        }
    }

    /** A spoken request: the title whose name matches, else the best match, as in the existing app. */
    fun playFromSearch(query: String) {
        graph.scope.future {
            val playable = runSearch(query).filter { it.mediaMetadata.isPlayable == true }
            (playable.firstOrNull { it.mediaMetadata.title.toString().equals(query.trim(), ignoreCase = true) } ?: playable.firstOrNull())?.let { open(it.mediaId) }
        }
    }

    /** Opens a selected browse or search entry, from the phone's copy when it has a complete one. */
    fun open(mediaId: String) {
        val parts = mediaId.split('/')
        if (parts.firstOrNull() == "download") {
            graph.downloads.records.value.firstOrNull { it.id == parts.getOrNull(1) }?.takeIf(::usable)?.let { graph.playback.play(graph.downloads.localSource(it)) }
            return
        }
        val api = client ?: return
        val (itemId, episodeId) = when (parts.firstOrNull()) {
            "item" -> parts[1] to null
            "episode" -> parts[1] to parts[2]
            else -> return
        }
        val local = graph.downloads.find(api.account, itemId, episodeId)?.takeIf(::usable)
        graph.playback.play(local?.let { graph.downloads.localSource(it) } ?: PlaySource.Stream(api, itemId, episodeId, api.coverUrl(itemId).toString(), null))
    }

    fun resumption(): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val last = graph.settings.current.lastPlayed ?: return Futures.immediateFailedFuture(UnsupportedOperationException("Nothing to resume"))
        return Futures.immediateFuture(MediaSession.MediaItemsWithStartPosition(listOf(MediaItem.Builder().setMediaId(last).build()), 0, 0))
    }

    private fun folder(id: String, title: String, subtitle: String? = null, artwork: String? = null) = MediaItem.Builder().setMediaId(id)
        .setMediaMetadata(
            MediaMetadata.Builder().setTitle(title).setSubtitle(subtitle).setArtworkUri(artwork?.let(Uri::parse))
                .setIsBrowsable(true).setIsPlayable(false).setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED).build(),
        )
        .build()

    private fun playable(item: LibraryItem, api: ApiClient, progress: Map<Pair<String, String?>, MediaProgress>, prefix: String = ""): MediaItem {
        val episode = item.recentEpisode
        val record = graph.downloads.find(api.account, item.id, episode?.id)?.takeIf(::usable)
        val extras = Bundle().apply {
            progress[item.id to episode?.id]?.let { done ->
                putInt(EXTRA_COMPLETION_STATUS, if (done.isFinished) STATUS_FINISHED else if (done.progress > 0 || done.currentTime > 0) STATUS_STARTED else STATUS_NOT_STARTED)
                if (!done.isFinished && done.progress > 0) putDouble(EXTRA_COMPLETION_PERCENTAGE, done.progress)
            }
            if (record != null) putLong(EXTRA_DOWNLOAD_STATUS, STATUS_DOWNLOADED)
        }
        return MediaItem.Builder()
            .setMediaId(if (episode != null) "episode/${item.id}/${episode.id}" else "item/${item.id}")
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(prefix + (episode?.title ?: item.title)).setArtist(if (episode != null) item.title else item.author)
                    .setArtworkUri(Uri.parse(api.coverUrl(item.id).toString())).setIsBrowsable(false).setIsPlayable(true).setExtras(extras)
                    .setMediaType(if (item.isPodcast) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK).build(),
            )
            .build()
    }

    companion object {
        const val ROOT = "root"
        const val CONTINUE = "continue"
        const val RECENT = "recent"
        const val LIBRARIES = "libraries"
        const val DOWNLOADS = "downloads"
        private val RECENT_SHELVES = setOf("recently-added", "recent-series", "newest-episodes", "newest-authors")

        // The car's own keys (androidx.media.utils.MediaConstants), spelled out to avoid another library for constants.
        private const val EXTRA_COMPLETION_STATUS = "android.media.extra.PLAYBACK_STATUS"
        private const val EXTRA_COMPLETION_PERCENTAGE = "androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE"
        private const val EXTRA_DOWNLOAD_STATUS = "android.media.extra.DOWNLOAD_STATUS"
        private const val STATUS_NOT_STARTED = 0
        private const val STATUS_STARTED = 1
        private const val STATUS_FINISHED = 2
        private const val STATUS_DOWNLOADED = 2L
    }
}
