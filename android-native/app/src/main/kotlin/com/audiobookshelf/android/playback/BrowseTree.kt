package com.audiobookshelf.android.playback

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionError
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.LibraryItem
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.guava.future

/**
 * Browse tree for Android Auto and other media browsers. IDs: `root`, `continue`, `libraries`,
 * `library/<id>`, `item/<id>`, `episode/<itemId>/<episodeId>`.
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
            val api = client ?: return@future LibraryResult.ofError(SessionError.ERROR_SESSION_AUTHENTICATION_EXPIRED)
            try {
                val children: List<MediaItem> = when {
                    parentId == ROOT -> listOf(folder(CONTINUE, "Continue"), folder(LIBRARIES, "Libraries"))
                    parentId == CONTINUE -> {
                        val library = graph.accounts.activeLibraryId() ?: api.libraries().firstOrNull()?.id
                        library?.let { id -> api.personalized(id).firstOrNull { it.id == "continue-listening" }?.items().orEmpty().map { playable(it, api) } }.orEmpty()
                    }
                    parentId == LIBRARIES -> api.libraries().map { folder("library/${it.id}", it.name) }
                    parentId.startsWith("library/") -> api.items(parentId.removePrefix("library/"), page, limit = pageSize.coerceIn(1, 100)).results.map { playable(it, api) }
                    else -> emptyList()
                }
                LibraryResult.ofItemList(children, params)
            } catch (failure: Exception) {
                graph.accounts.handle(failure)
                LibraryResult.ofError(SessionError.ERROR_IO)
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
        return libraries.flatMap { library ->
            runCatching { api.search(library.id, query) }.getOrNull()?.let { result -> (result.book + result.podcast).map { playable(it.libraryItem, api) } }.orEmpty()
        }
    }

    /** Opens a selected browse or search entry; an empty or unknown ID resumes or starts the first title. */
    fun open(mediaId: String) {
        val api = client ?: return
        val parts = mediaId.split('/')
        when (parts.firstOrNull()) {
            "item" -> graph.playback.play(PlaySource.Stream(api, parts[1], null, api.coverUrl(parts[1]).toString(), null))
            "episode" -> graph.playback.play(PlaySource.Stream(api, parts[1], parts[2], api.coverUrl(parts[1]).toString(), null))
        }
    }

    fun resumption(): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val last = graph.settings.current.lastPlayed ?: return Futures.immediateFailedFuture(UnsupportedOperationException("Nothing to resume"))
        return Futures.immediateFuture(MediaSession.MediaItemsWithStartPosition(listOf(MediaItem.Builder().setMediaId(last).build()), 0, 0))
    }

    private fun folder(id: String, title: String) = MediaItem.Builder().setMediaId(id)
        .setMediaMetadata(MediaMetadata.Builder().setTitle(title).setIsBrowsable(true).setIsPlayable(false).setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED).build())
        .build()

    private fun playable(item: LibraryItem, api: ApiClient): MediaItem {
        val episode = item.recentEpisode
        return MediaItem.Builder()
            .setMediaId(if (episode != null) "episode/${item.id}/${episode.id}" else "item/${item.id}")
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(episode?.title ?: item.title).setArtist(if (episode != null) item.title else item.author)
                    .setArtworkUri(Uri.parse(api.coverUrl(item.id).toString())).setIsBrowsable(false).setIsPlayable(true)
                    .setMediaType(if (item.isPodcast) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK).build(),
            )
            .build()
    }

    companion object {
        const val ROOT = "root"
        const val CONTINUE = "continue"
        const val LIBRARIES = "libraries"
    }
}
