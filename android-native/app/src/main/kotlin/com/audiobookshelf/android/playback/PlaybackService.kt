package com.audiobookshelf.android.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DataSourceBitmapLoader
import androidx.media3.session.CacheBitmapLoader
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.audiobookshelf.android.MainActivity
import com.audiobookshelf.android.R
import com.audiobookshelf.android.graph
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * Exposes the engine's player to the notification, lock screen, headsets, Bluetooth and Android
 * Auto. Track skips from those surfaces become jumps, as in the existing app, because one book is
 * several files and "next file" is never what a listener means.
 */
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null
    private val engine get() = graph.playback

    override fun onCreate() {
        super.onCreate()
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).putExtra(MainActivity.EXTRA_OPEN_PLAYER, true),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaLibrarySession.Builder(this, SystemPlayer(engine, browse), LibraryCallback(this))
            .setSessionActivity(open)
            .setMediaButtonPreferences(buttons())
            .setBitmapLoader(CacheBitmapLoader(DataSourceBitmapLoader.Builder(this).setDataSourceFactory(engine.mediaDataSource).build()))
            .build()
            // Playback starts from the app's own UI with no controller bound, so the service must track the session itself to post its notification.
            .also(::addSession)
    }

    private fun buttons(): ImmutableList<CommandButton> = ImmutableList.of(
        CommandButton.Builder(CommandButton.ICON_SKIP_BACK).setDisplayName(getString(R.string.jump_back))
            .setPlayerCommand(Player.COMMAND_SEEK_BACK).setSlots(CommandButton.SLOT_BACK).build(),
        CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD).setDisplayName(getString(R.string.jump_forward))
            .setPlayerCommand(Player.COMMAND_SEEK_FORWARD).setSlots(CommandButton.SLOT_FORWARD).build(),
        CommandButton.Builder(CommandButton.ICON_PLAYBACK_SPEED).setDisplayName(getString(R.string.playback_speed))
            .setSessionCommand(SessionCommand(COMMAND_SPEED, Bundle.EMPTY)).setSlots(CommandButton.SLOT_OVERFLOW).build(),
    )

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        // The engine owns the player for the whole process; only the session ends here.
        session?.release()
        session = null
        super.onDestroy()
    }

    private inner class LibraryCallback(private val service: PlaybackService) : MediaLibrarySession.Callback {
        override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
            val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon().add(SessionCommand(COMMAND_SPEED, Bundle.EMPTY)).build()
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session).setAvailableSessionCommands(commands).setMediaButtonPreferences(buttons()).build()
        }

        override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo, customCommand: SessionCommand, args: Bundle): ListenableFuture<SessionResult> {
            if (customCommand.customAction == COMMAND_SPEED) {
                engine.setSpeed(nextSpeed(engine.state.value.speed))
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return super.onCustomCommand(session, controller, customCommand, args)
        }

        override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> =
            service.browse.root(params)

        override fun onGetChildren(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
            service.browse.children(parentId, page, pageSize, params)

        override fun onGetItem(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, mediaId: String): ListenableFuture<LibraryResult<MediaItem>> =
            service.browse.item(mediaId)

        override fun onSearch(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> =
            service.browse.search(session, browser, query, params)

        override fun onGetSearchResult(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
            service.browse.searchResult(query, page, pageSize, params)

        override fun onAddMediaItems(mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>): ListenableFuture<MutableList<MediaItem>> =
            Futures.immediateFuture(mediaItems)

        override fun onPlaybackResumption(mediaSession: MediaSession, controller: MediaSession.ControllerInfo, isForPlayback: Boolean): ListenableFuture<MediaSession.MediaItemsWithStartPosition> =
            service.browse.resumption()
    }

    internal val browse by lazy { BrowseTree(this) }

    companion object {
        const val COMMAND_SPEED = "com.audiobookshelf.android.SPEED"
        private val speeds = listOf(0.5f, 1f, 1.2f, 1.5f, 2f, 3f)

        /** The existing app's speed cycle for system controls; anything above 3x returns to 1x. */
        fun nextSpeed(current: Float): Float = if (current > 3f) 1f else speeds.firstOrNull { it > current + 0.01f } ?: speeds.first()
    }
}

/** The engine's player as system surfaces see it: jumps instead of file skips, auto-rewind on play. */
private class SystemPlayer(private val engine: PlaybackEngine, private val browse: BrowseTree) : ForwardingSimpleBasePlayer(engine.player) {
    /** Browse and search selections arrive as media IDs; the engine opens the real media for them. */
    override fun handleSetMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<*> {
        mediaItems.getOrNull(startIndex.coerceAtLeast(0))?.let { browse.open(it.mediaId) }
        return Futures.immediateVoidFuture()
    }

    override fun handlePrepare(): ListenableFuture<*> {
        if (engine.player.mediaItemCount > 0) engine.player.prepare()
        return Futures.immediateVoidFuture()
    }

    override fun getState(): State {
        val state = super.getState()
        val allowSeek = engine.allowSystemSeeking()
        val commands = state.availableCommands.buildUpon()
            .addAll(Player.COMMAND_SEEK_BACK, Player.COMMAND_SEEK_FORWARD, Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS)
            .remove(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM).remove(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            .apply { if (!allowSeek) remove(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM) }
            .build()
        return state.buildUpon().setAvailableCommands(commands).build()
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (playWhenReady) engine.resume() else engine.pause()
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        when (seekCommand) {
            Player.COMMAND_SEEK_BACK, Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> engine.jump(forward = false)
            Player.COMMAND_SEEK_FORWARD, Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> engine.jump(forward = true)
            else -> return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
        }
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        engine.pause()
        return Futures.immediateVoidFuture()
    }
}
