package com.audiobookshelf.android.playback

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.AudioTrack
import com.audiobookshelf.core.Chapter
import com.audiobookshelf.core.DeviceInfo
import com.audiobookshelf.core.ListeningJournal
import com.audiobookshelf.core.ListeningMedia
import com.audiobookshelf.core.Timeline
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.Interceptor
import okhttp3.OkHttpClient

/** What is loaded in the player, independent of whether it streams or plays downloaded files. */
data class NowPlaying(
    val itemId: String,
    val episodeId: String?,
    val title: String,
    val author: String,
    val coverUrl: String?,
    val chapters: List<Chapter>,
    val duration: Double,
    val isPodcast: Boolean,
    val local: Boolean,
)

data class PlayerState(
    val now: NowPlaying? = null,
    val loading: Boolean = false,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val position: Double = 0.0,
    val speed: Float = 1f,
    val finished: Boolean = false,
    /** Failure after media was opened; retry reopens at the same position. */
    val error: String? = null,
    /** Failure opening an item, keyed by `itemId/episodeId` so the item screen can explain it. */
    val openError: Pair<String, String>? = null,
)

/** A media source the engine can open: server stream or files already on this device. */
sealed interface PlaySource {
    val account: AccountIdentity
    val itemId: String
    val episodeId: String?

    data class Stream(val client: ApiClient, override val itemId: String, override val episodeId: String?, val coverUrl: String?, val remoteUpdatedAt: Double?) : PlaySource {
        override val account get() = client.account
    }

    data class Local(
        override val account: AccountIdentity, override val itemId: String, override val episodeId: String?,
        val title: String, val author: String, val coverUri: String?, val mediaType: String,
        val tracks: List<AudioTrack>, val files: List<Uri>, val chapters: List<Chapter>, val startTime: Double,
    ) : PlaySource
}

fun itemKey(itemId: String, episodeId: String?) = "$itemId/${episodeId.orEmpty()}"

/**
 * Owns the one ExoPlayer for the process. The media session service exposes it to the system; the
 * UI observes [state]. Listening is journaled before publication so it survives process death.
 */
class PlaybackEngine(
    private val context: Context,
    private val scope: CoroutineScope,
    private val http: OkHttpClient,
    private val settings: SettingsStore,
    private val accounts: AccountStore,
    private val journal: ListeningJournal,
    private val sync: ProgressSync,
    private val device: () -> DeviceInfo,
    private val io: CoroutineDispatcher,
) {
    private class Loaded(
        val source: PlaySource,
        val now: NowPlaying,
        var timeline: Timeline,
        val recordId: String,
        var streamSessionId: String?,
        var transcoded: Boolean,
        var lastTick: Long = SystemClock.elapsedRealtime(),
        var unrecordedListening: Double = 0.0,
        var lastRecord: Long = SystemClock.elapsedRealtime(),
        var lastPublish: Long = SystemClock.elapsedRealtime(),
        var lastRecordedPosition: Double = -1.0,
    )

    private val mutable = MutableStateFlow(PlayerState(speed = settings.current.playbackRate))
    val state: StateFlow<PlayerState> = mutable

    private var loaded: Loaded? = null
    private var generation = 0
    private var ticker: Job? = null
    /** Wall-clock time of the last user pause; 0 after a seek, matching the existing app's auto-rewind. */
    private var pausedAt = 0L

    val player: ExoPlayer by lazy { buildPlayer() }

    // region Commands
    fun play(source: PlaySource) {
        val current = loaded
        if (current != null && current.source.itemId == source.itemId && current.source.episodeId == source.episodeId && mutable.value.error == null) {
            if (mutable.value.finished) seekTo(0.0)
            resume()
            return
        }
        val request = ++generation
        stopCurrent(closeStream = true)
        mutable.value = mutable.value.copy(now = null, loading = true, error = null, openError = null, finished = false, position = 0.0)
        startService()
        scope.launch {
            try {
                open(source, request, transcode = false, at = null)
            } catch (failure: Exception) {
                if (request != generation) return@launch
                Log.w(TAG, "Could not open ${source.itemId}", failure)
                accounts.handle(failure)
                mutable.value = mutable.value.copy(loading = false, openError = itemKey(source.itemId, source.episodeId) to describe(failure))
            }
        }
    }

    fun resume() {
        val current = loaded ?: return
        val since = if (pausedAt > 0) System.currentTimeMillis() - pausedAt else 0
        if (pausedAt > 0 && !settings.current.disableAutoRewind) {
            val rewind = autoRewindSeconds(since)
            if (rewind > 0) {
                val position = globalPosition()
                val floor = current.timeline.chapterAt(position)?.start ?: 0.0
                seekInternal((position - rewind).coerceAtLeast(floor))
            }
        }
        pausedAt = 0
        if (player.playbackState == Player.STATE_IDLE) player.prepare()
        player.play()
    }

    fun pause() {
        player.pause()
    }

    fun toggle() = if (player.playWhenReady) pause() else resume()

    fun seekTo(position: Double) {
        pausedAt = 0
        seekInternal(position)
        mutable.value = mutable.value.copy(finished = false)
        persist(force = true)
    }

    fun jump(forward: Boolean) {
        val step = if (forward) settings.current.jumpForwardTime else -settings.current.jumpBackwardsTime
        seekTo(globalPosition() + step)
    }

    fun seekChapter(index: Int) {
        val chapter = loaded?.now?.chapters?.getOrNull(index) ?: return
        seekTo(chapter.start)
    }

    fun previousChapter() {
        val current = loaded ?: return
        val position = globalPosition()
        val index = current.timeline.chapterIndex(position)
        val chapter = current.now.chapters.getOrNull(index) ?: return seekTo(0.0)
        // Like most players: a few seconds into a chapter, "previous" restarts it.
        if (position - chapter.start > 3 || index == 0) seekTo(chapter.start) else seekChapter(index - 1)
    }

    fun nextChapter() {
        val current = loaded ?: return
        val index = current.timeline.chapterIndex(globalPosition())
        if (index + 1 < current.now.chapters.size) seekChapter(index + 1) else seekTo(current.timeline.duration)
    }

    fun setSpeed(speed: Float) {
        val value = speed.coerceIn(0.5f, 10f)
        settings.update { it.copy(playbackRate = value) }
        player.setPlaybackSpeed(value)
        mutable.value = mutable.value.copy(speed = value)
    }

    fun retry() {
        val current = loaded ?: return
        val position = globalPosition()
        val request = ++generation
        mutable.value = mutable.value.copy(error = null, loading = true)
        scope.launch {
            try {
                if (current.source is PlaySource.Stream) current.streamSessionId?.let { closeStream(current.source.client, it) }
                loaded = null
                reopen(current, request, position)
            } catch (failure: Exception) {
                if (request == generation) {
                    loaded = current
                    mutable.value = mutable.value.copy(loading = false, error = describe(failure))
                }
            }
        }
    }

    /** Stops playback, publishes listening, and closes the server stream session. */
    fun close() {
        generation++
        stopCurrent(closeStream = true)
        mutable.value = PlayerState(speed = mutable.value.speed)
    }

    fun allowSystemSeeking() = settings.current.allowSeekingOnMediaControls

    fun isLoaded(itemId: String, episodeId: String?) = loaded?.let { it.source.itemId == itemId && it.source.episodeId == episodeId } == true
    // endregion

    private suspend fun open(source: PlaySource, request: Int, transcode: Boolean, at: Double?) {
        val media: Opened = when (source) {
            is PlaySource.Stream -> openStream(source, transcode, at)
            is PlaySource.Local -> openLocal(source, at)
        }
        if (request != generation) {
            media.streamSessionId?.let { if (source is PlaySource.Stream) closeStream(source.client, it) }
            return
        }
        val timeline = Timeline(media.tracks, media.now.chapters)
        val recordId = withContext(io) {
            journal.begin(source.account, ListeningMedia(source.itemId, source.episodeId, media.now.title, media.now.author,
                if (source.episodeId != null || media.now.isPodcast) "podcast" else "book", timeline.duration, media.start,
                playMethod = if (source is PlaySource.Local) 3 else 0), device().deviceId)
        }
        val current = Loaded(source, media.now.copy(duration = timeline.duration), timeline, recordId, media.streamSessionId, transcode)
        if (source is PlaySource.Stream) settings.update { it.copy(lastPlayed = source.episodeId?.let { episode -> "episode/${source.itemId}/$episode" } ?: "item/${source.itemId}") }
        loaded = current
        load(current, media.items, media.start)
    }

    private suspend fun reopen(previous: Loaded, request: Int, position: Double) {
        val media = when (val source = previous.source) {
            is PlaySource.Stream -> openStream(source, transcode = false, at = position)
            is PlaySource.Local -> openLocal(source, at = position)
        }
        if (request != generation) return
        previous.timeline = Timeline(media.tracks, previous.now.chapters)
        previous.streamSessionId = media.streamSessionId
        previous.transcoded = false
        loaded = previous
        load(previous, media.items, position)
    }

    private class Opened(val now: NowPlaying, val tracks: List<AudioTrack>, val items: List<MediaItem>, val start: Double, val streamSessionId: String?)

    private suspend fun openStream(source: PlaySource.Stream, transcode: Boolean, at: Double?): Opened {
        val session = source.client.play(source.itemId, source.episodeId, transcode)
        val title = session.displayTitle ?: "Untitled"
        val author = session.displayAuthor.orEmpty()
        val tracks = session.audioTracks.sortedBy { it.index ?: 0 }
        val timeline = Timeline(tracks, session.chapters)
        val duration = timeline.duration.takeIf { it > 0 } ?: session.duration
        val cached = withContext(io) { journal.cachedPosition(source.account, source.itemId, source.episodeId, newerThan = source.remoteUpdatedAt ?: Double.MAX_VALUE) }
        var start = at ?: cached ?: session.currentTime
        if (at == null && duration - start < 5) start = 0.0
        Log.i(TAG, "Opening at $start (requested $at, journal $cached, server ${session.currentTime})")
        val now = NowPlaying(source.itemId, source.episodeId, title, author, source.coverUrl, session.chapters, duration, source.episodeId != null, local = false)
        val items = tracks.mapIndexed { index, track ->
            val url = source.client.mediaUrl(track.contentUrl ?: throw ApiError.NoAudio())
            mediaItem("${source.itemId}/${source.episodeId.orEmpty()}/$index", url.toString(), now, track.mimeType)
        }
        return Opened(now, tracks, items, start.coerceIn(0.0, duration), session.id)
    }

    private fun openLocal(source: PlaySource.Local, at: Double?): Opened {
        val timeline = Timeline(source.tracks, source.chapters)
        val now = NowPlaying(source.itemId, source.episodeId, source.title, source.author, source.coverUri, source.chapters, timeline.duration, source.mediaType == "podcast", local = true)
        val items = source.files.mapIndexed { index, uri -> mediaItem("${source.itemId}/${source.episodeId.orEmpty()}/$index", uri.toString(), now, source.tracks.getOrNull(index)?.mimeType) }
        val start = at ?: source.startTime.let { if (timeline.duration - it < 5) 0.0 else it }
        return Opened(now, source.tracks, items, start, null)
    }

    private fun mediaItem(id: String, uri: String, now: NowPlaying, mime: String?): MediaItem = MediaItem.Builder()
        .setMediaId(id)
        .setUri(uri)
        .apply { if (mime == "application/vnd.apple.mpegurl" || uri.contains(".m3u8")) setMimeType(androidx.media3.common.MimeTypes.APPLICATION_M3U8) }
        .setMediaMetadata(
            MediaMetadata.Builder().setTitle(now.title).setArtist(now.author).setAlbumTitle(now.title)
                .setArtworkUri(now.coverUrl?.let(Uri::parse)).setIsPlayable(true).setIsBrowsable(false)
                .setMediaType(if (now.isPodcast) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK).build(),
        )
        .build()

    private fun load(current: Loaded, items: List<MediaItem>, start: Double) {
        val location = current.timeline.locate(start)
        player.setMediaItems(items, location.trackIndex, (location.offset * 1000).toLong())
        player.setPlaybackSpeed(settings.current.playbackRate)
        player.prepare()
        player.play()
        pausedAt = 0
        mutable.value = mutable.value.copy(now = current.now, loading = false, error = null, openError = null, position = start, speed = settings.current.playbackRate, finished = false)
        startTicker()
    }

    private fun stopCurrent(closeStream: Boolean) {
        val current = loaded ?: return
        loaded = null
        ticker?.cancel()
        persist(current, force = true)
        player.stop()
        player.clearMediaItems()
        scope.launch {
            withContext(io) { journal.finish(current.recordId) }
            sync.publish(current.source.account)
            val source = current.source
            if (closeStream && source is PlaySource.Stream) current.streamSessionId?.let { closeStream(source.client, it) }
        }
    }

    private suspend fun closeStream(client: ApiClient, sessionId: String) {
        runCatching { client.closeSession(sessionId) }.onFailure { Log.i(TAG, "Stream session close deferred: ${it.javaClass.simpleName}") }
    }

    // region Listening accounting
    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                tick()
                delay(500)
            }
        }
    }

    private fun tick() {
        val current = loaded ?: return
        val now = SystemClock.elapsedRealtime()
        if (player.isPlaying) current.unrecordedListening += (now - current.lastTick) / 1000.0
        current.lastTick = now
        mutable.value = mutable.value.copy(position = globalPosition())
        if (now - current.lastRecord >= RECORD_INTERVAL_MS) persist(current, force = false)
        if (player.isPlaying && now - current.lastPublish >= PUBLISH_INTERVAL_MS) {
            current.lastPublish = now
            scope.launch { sync.publish(current.source.account) }
        }
    }

    private fun persist(force: Boolean) { loaded?.let { persist(it, force) } }

    private fun persist(current: Loaded, force: Boolean) {
        val position = globalPosition(current)
        val listened = current.unrecordedListening
        if (!force && listened <= 0 && position == current.lastRecordedPosition) return
        current.unrecordedListening = 0.0
        current.lastRecord = SystemClock.elapsedRealtime()
        current.lastRecordedPosition = position
        scope.launch(io) {
            runCatching { journal.record(current.recordId, position, listened) }.onFailure { Log.w(TAG, "Listening not recorded", it) }
        }
    }
    // endregion

    private fun globalPosition(current: Loaded? = loaded): Double {
        current ?: return 0.0
        if (player.mediaItemCount == 0) return mutable.value.position
        return current.timeline.position(player.currentMediaItemIndex, player.currentPosition / 1000.0)
    }

    private fun seekInternal(position: Double) {
        val current = loaded ?: return
        val target = position.coerceIn(0.0, current.timeline.duration)
        val location = current.timeline.locate(target)
        player.seekTo(location.trackIndex, (location.offset * 1000).toLong())
        mutable.value = mutable.value.copy(position = target)
    }

    private fun onEnded() {
        val current = loaded ?: return
        val end = current.timeline.duration
        mutable.value = mutable.value.copy(position = end, finished = true, playing = false)
        current.lastRecordedPosition = -1.0
        scope.launch(io) { runCatching { journal.record(current.recordId, end, current.unrecordedListening.also { current.unrecordedListening = 0.0 }) } }
            .invokeOnCompletion { scope.launch { sync.publish(current.source.account) } }
    }

    private fun onError(error: PlaybackException) {
        val current = loaded ?: return
        Log.w(TAG, "Playback failed", error)
        val source = current.source
        if (source is PlaySource.Stream && !current.transcoded) {
            // The existing app retries a failed direct play once as a server transcode.
            val position = globalPosition()
            val request = ++generation
            current.transcoded = true
            scope.launch {
                try {
                    current.streamSessionId?.let { closeStream(source.client, it) }
                    val media = openStream(source, transcode = true, at = position)
                    if (request != generation) return@launch
                    current.timeline = Timeline(media.tracks, current.now.chapters)
                    current.streamSessionId = media.streamSessionId
                    load(current, media.items, position)
                } catch (failure: Exception) {
                    if (request == generation) fail(current, failure.message ?: error.message)
                }
            }
            return
        }
        fail(current, error.message)
    }

    private fun fail(current: Loaded, message: String?) {
        persist(current, force = true)
        mutable.value = mutable.value.copy(error = "Playback stopped: ${message ?: "the audio could not be loaded"}. Your position is kept.", playing = false, loading = false)
        scope.launch { sync.publish(current.source.account) }
    }

    private fun describe(failure: Throwable): String = when (failure) {
        is ApiError.NoAudio -> "This item has no playable audio."
        else -> failure.message ?: "Playback could not start."
    }

    private fun startService() {
        runCatching { ContextCompat.startForegroundService(context, Intent(context, PlaybackService::class.java)) }
            .onFailure { runCatching { context.startService(Intent(context, PlaybackService::class.java)) } }
    }

    /** Audio and artwork requests carry the bearer of the account that opened them, and only to that server. */
    val mediaDataSource: DataSource.Factory by lazy {
        val auth = Interceptor { chain ->
            val request = chain.request()
            val client = (loaded?.source as? PlaySource.Stream)?.client ?: accounts.activeClient
            val token = client?.takeIf { it.owns(request.url) }?.let { runCatching { runBlocking { it.bearer() } }.getOrNull() }
            chain.proceed(if (token != null) request.newBuilder().header("Authorization", "Bearer $token").build() else request)
        }
        DefaultDataSource.Factory(context, OkHttpDataSource.Factory(http.newBuilder().addInterceptor(auth).build()))
    }

    private fun buildPlayer(): ExoPlayer {
        val sources = DefaultMediaSourceFactory(mediaDataSource)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(2))
        val loadControl = DefaultLoadControl.Builder().setBufferDurationsMs(20_000, 45_000, 5_000, 20_000).build()
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(sources)
            .setLoadControl(loadControl)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setSeekBackIncrementMs(settings.current.jumpBackwardsTime * 1000L)
            .setSeekForwardIncrementMs(settings.current.jumpForwardTime * 1000L)
            .build()
            .also { player ->
                player.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        mutable.value = mutable.value.copy(playing = player.playWhenReady && mutable.value.error == null)
                        if (!isPlaying) persist(force = true)
                    }

                    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                        mutable.value = mutable.value.copy(playing = playWhenReady && mutable.value.error == null)
                        if (!playWhenReady && reason != Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM) {
                            pausedAt = System.currentTimeMillis()
                            persist(force = true)
                            loaded?.let { current -> scope.launch { sync.publish(current.source.account) } }
                        }
                        if (playWhenReady) player.volume = 1f
                    }

                    override fun onPlaybackStateChanged(state: Int) {
                        mutable.value = mutable.value.copy(buffering = state == Player.STATE_BUFFERING)
                        if (state == Player.STATE_ENDED) onEnded()
                    }

                    override fun onPositionDiscontinuity(old: Player.PositionInfo, new: Player.PositionInfo, reason: Int) {
                        if (reason == Player.DISCONTINUITY_REASON_SEEK) pausedAt = 0
                    }

                    override fun onPlayerError(error: PlaybackException) = onError(error)
                })
            }
    }

    companion object {
        private const val TAG = "AbsPlayback"
        private const val RECORD_INTERVAL_MS = 5_000L
        private const val PUBLISH_INTERVAL_MS = 15_000L

        /** Same thresholds as the existing Android app, keyed by how long playback was paused. */
        fun autoRewindSeconds(pausedMs: Long): Double = when {
            pausedMs < 10_000 -> 0.0
            pausedMs < 60_000 -> 3.0
            pausedMs < 300_000 -> 10.0
            pausedMs < 1_800_000 -> 20.0
            else -> 29.5
        }
    }
}
