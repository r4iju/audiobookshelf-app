package com.audiobookshelf.android.playback

import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player

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

internal data class CastOutput(val player: Player, val pauseTransfer: () -> Unit)
