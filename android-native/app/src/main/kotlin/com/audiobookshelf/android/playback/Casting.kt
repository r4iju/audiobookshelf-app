package com.audiobookshelf.android.playback

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.MediaItemConverter
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.images.WebImage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject

/** The Audiobookshelf receiver registered by the existing app. */
private const val RECEIVER_ID = "FD1F76C5"

class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions = CastOptions.Builder()
        .setReceiverApplicationId(RECEIVER_ID)
        // The app's media session and notification already follow the cast player.
        .setCastMediaOptions(CastMediaOptions.Builder().setMediaSessionEnabled(false).setNotificationOptions(null).build())
        .setStopReceiverApplicationWhenEndingSession(true)
        .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}

/** Extras a streamed media item carries so it can be handed to a receiver. */
internal object CastExtras {
    const val URL = "abs.castUrl"
    const val MIME = "abs.castMime"
    const val DURATION = "abs.castDuration"

    fun of(url: String, mime: String?, duration: Double) = Bundle().apply {
        putString(URL, url); putString(MIME, mime); putDouble(DURATION, duration)
    }

    fun castable(item: MediaItem) = item.mediaMetadata.extras?.getString(URL) != null
}

/** Sends the receiver its own track URL and keeps the phone's URL to return to when casting ends. */
internal class CastConverter : MediaItemConverter {
    override fun toMediaQueueItem(mediaItem: MediaItem): MediaQueueItem {
        val meta = mediaItem.mediaMetadata
        val extras = meta.extras ?: throw IllegalArgumentException("Downloaded media cannot be cast")
        val url = extras.getString(CastExtras.URL) ?: throw IllegalArgumentException("Downloaded media cannot be cast")
        val castMeta = com.google.android.gms.cast.MediaMetadata(com.google.android.gms.cast.MediaMetadata.MEDIA_TYPE_AUDIOBOOK_CHAPTER).apply {
            putString(com.google.android.gms.cast.MediaMetadata.KEY_TITLE, meta.title?.toString().orEmpty())
            putString(com.google.android.gms.cast.MediaMetadata.KEY_ARTIST, meta.artist?.toString().orEmpty())
            putString(com.google.android.gms.cast.MediaMetadata.KEY_ALBUM_TITLE, meta.albumTitle?.toString().orEmpty())
            meta.artworkUri?.let { addImage(WebImage(it)) }
        }
        val phone = JSONObject().put("mediaId", mediaItem.mediaId).put("uri", mediaItem.localConfiguration?.uri?.toString())
            .put("mime", mediaItem.localConfiguration?.mimeType).put("title", meta.title?.toString()).put("artist", meta.artist?.toString())
            .put("artwork", meta.artworkUri?.toString()).put("podcast", meta.mediaType == MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE)
            .put("castUrl", url).put("castMime", extras.getString(CastExtras.MIME)).put("duration", extras.getDouble(CastExtras.DURATION))
        val info = MediaInfo.Builder(url)
            .setContentUrl(url)
            .setContentType(extras.getString(CastExtras.MIME) ?: "audio/mpeg")
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setMetadata(castMeta)
            .setCustomData(phone)
            .build()
        return MediaQueueItem.Builder(info).setPlaybackDuration(extras.getDouble(CastExtras.DURATION)).build()
    }

    override fun toMediaItem(mediaQueueItem: MediaQueueItem): MediaItem {
        val phone = mediaQueueItem.media?.customData ?: JSONObject()
        val extras = CastExtras.of(phone.optString("castUrl"), phone.optString("castMime").ifEmpty { null }, phone.optDouble("duration", 0.0))
        return MediaItem.Builder()
            .setMediaId(phone.optString("mediaId"))
            .setUri(phone.optString("uri").ifEmpty { mediaQueueItem.media?.contentId })
            .apply { phone.optString("mime").ifEmpty { null }?.let(::setMimeType) }
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(phone.optString("title")).setArtist(phone.optString("artist")).setAlbumTitle(phone.optString("title"))
                    .setArtworkUri(phone.optString("artwork").ifEmpty { null }?.let(Uri::parse)).setIsPlayable(true).setIsBrowsable(false)
                    .setMediaType(if (phone.optBoolean("podcast")) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK)
                    .setExtras(extras).build(),
            )
            .build()
    }
}

/**
 * What moves between the phone and a receiver when Media3 switches players. The switch itself cannot
 * be refused, so a downloaded title is kept on the phone, which Media3 only stops, and the receiver
 * session is ended; when Media3 switches back, the phone resumes where it was.
 */
internal class CastHandover(
    private val phone: Player,
    private val endSession: () -> Unit,
    private val explain: (String) -> Unit,
    /** True while the engine holds an opened title, bound to its account and listening record. */
    private val hasTitle: () -> Boolean,
) {

    private var keptOnPhone = false
    private var resume = false

    fun transfer(from: Player, to: Player) {
        when {
            to !== phone && (0 until from.mediaItemCount).any { !CastExtras.castable(from.getMediaItemAt(it)) } -> {
                keptOnPhone = true
                resume = from.playWhenReady
                explain(DOWNLOAD_NOT_CASTABLE)
                endSession()
            }
            to === phone && keptOnPhone -> {
                keptOnPhone = false
                phone.playWhenReady = resume
            }
            // A receiver queue no open title accounts for, such as one left by a process that died, stays off the phone.
            to === phone && !hasTitle() -> Unit
            else -> CastPlayer.TransferCallback.DEFAULT.transferState(from, to)
        }
    }

    companion object {
        const val DOWNLOAD_NOT_CASTABLE = "Downloaded copies play on this phone only. Stop casting to listen here, or stream the title instead."
    }
}

data class CastReceiver(val id: String, val name: String, val description: String?)

data class CastStatus(
    /** Why casting cannot be offered on this device, or null when it can. */
    val unavailable: String? = null,
    val receivers: List<CastReceiver> = emptyList(),
    val connectedTo: String? = null,
    val connecting: String? = null,
    /** The last connection that failed or dropped, explained for the listener. */
    val problem: String? = null,
)

/** Receiver discovery and selection. Discovery scans actively only while someone is looking. */
class CastRoutes(private val context: Context) {
    private val mutable = MutableStateFlow(CastStatus())
    val status: StateFlow<CastStatus> = mutable

    val castContext: CastContext? = run {
        val services = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
        if (services != ConnectionResult.SUCCESS) {
            mutable.value = CastStatus(unavailable = "Casting needs Google Play services, which this device does not have or needs to update.")
            null
        } else {
            @Suppress("DEPRECATION")
            runCatching { CastContext.getSharedInstance(context) }.getOrElse {
                mutable.value = CastStatus(unavailable = "Casting could not start on this device: ${it.message ?: it.javaClass.simpleName}.")
                null
            }
        }
    }

    private val router by lazy { MediaRouter.getInstance(context) }
    private val selector = MediaRouteSelector.Builder().addControlCategory(CastMediaControlIntent.categoryForCast(RECEIVER_ID)).build()
    private val callback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = refresh()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = refresh()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = refresh()
        override fun onRouteSelected(router: MediaRouter, route: MediaRouter.RouteInfo, reason: Int) = refresh()
        override fun onRouteUnselected(router: MediaRouter, route: MediaRouter.RouteInfo, reason: Int) = refresh()
    }
    private val sessions = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) = refresh()
        override fun onSessionStarted(session: CastSession, sessionId: String) = refresh(problem = null)
        override fun onSessionStartFailed(session: CastSession, error: Int) =
            refresh(problem = "Could not connect to ${mutable.value.connecting ?: "the receiver"}. Check that it is on and on the same Wi-Fi network as this phone.")
        override fun onSessionEnding(session: CastSession) = Unit
        override fun onSessionEnded(session: CastSession, error: Int) =
            refresh(problem = if (error != 0) "The connection to ${session.castDevice?.friendlyName ?: "the receiver"} was lost. Playback continues on this phone." else mutable.value.problem)
        override fun onSessionResuming(session: CastSession, sessionId: String) = refresh()
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = resumed()
        override fun onSessionResumeFailed(session: CastSession, error: Int) = refresh()
        override fun onSessionSuspended(session: CastSession, reason: Int) = refresh()
    }
    private var watchers = 0

    /** Whether a session the system resumes belongs to a title this process opened and accounts for. */
    var keepResumed: () -> Boolean = { false }

    /** Called for every resumed session, including the one the system restores after the app restarts. */
    internal fun resumed() {
        if (keepResumed()) return refresh(problem = null)
        mutable.value = mutable.value.copy(problem = RESUMED_WITHOUT_TITLE)
        castContext?.sessionManager?.endCurrentSession(true)
    }

    init {
        if (castContext != null) {
            router.addCallback(selector, callback)
            castContext.sessionManager.addSessionManagerListener(sessions, CastSession::class.java)
            refresh()
        }
    }

    /** Must be paired with [stopLooking]. */
    fun startLooking() {
        if (castContext == null) return
        if (watchers++ == 0) router.addCallback(selector, callback, MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN)
        refresh()
    }

    fun stopLooking() {
        if (castContext == null || watchers == 0) return
        if (--watchers == 0) router.addCallback(selector, callback)
    }

    fun connect(id: String) {
        router.routes.firstOrNull { it.id == id && it.matchesSelector(selector) }?.let { route ->
            mutable.value = mutable.value.copy(connecting = route.name, problem = null)
            router.selectRoute(route)
        }
    }

    /** Shows [problem] to the listener until the next connection attempt. */
    fun explain(problem: String) {
        mutable.value = mutable.value.copy(problem = problem)
    }

    fun disconnect() {
        castContext?.sessionManager?.endCurrentSession(true)
        refresh()
    }

    companion object {
        const val RESUMED_WITHOUT_TITLE = "Casting stopped because the app restarted while casting. Open the title again to keep listening from the last place this phone saved."
    }

    private fun refresh(problem: String? = mutable.value.problem) {
        if (castContext == null) return
        val selected = router.selectedRoute.takeIf { !it.isDefault && it.matchesSelector(selector) }
        val connected = castContext.sessionManager.currentCastSession?.takeIf { it.isConnected }?.castDevice?.friendlyName
        mutable.value = CastStatus(
            receivers = router.routes.filter { !it.isDefault && it.isEnabled && it.matchesSelector(selector) }
                .map { CastReceiver(it.id, it.name, it.description) },
            connectedTo = connected,
            connecting = selected?.name?.takeIf { connected == null && it == mutable.value.connecting },
            problem = problem,
        )
    }
}
