package com.audiobookshelf.android.playback

import android.content.Context
import androidx.media3.common.Player
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Public builds do not link the proprietary Cast SDK. */
class CastRoutes(@Suppress("UNUSED_PARAMETER") context: Context) {
    val available: Boolean = false
    val status: StateFlow<CastStatus> = MutableStateFlow(CastStatus(unavailable = "Chromecast is not included in this build."))
    var keepResumed: () -> Boolean = { false }
    fun startLooking() = Unit
    fun stopLooking() = Unit
    fun connect(@Suppress("UNUSED_PARAMETER") id: String) = Unit
    fun disconnect() = Unit
    fun explain(@Suppress("UNUSED_PARAMETER") problem: String) = Unit

    @Suppress("UNUSED_PARAMETER")
    internal fun createPlayer(phone: Player, back: Long, forward: Long, explain: (Int) -> Unit,
                              title: () -> Any?, endSession: () -> Unit): CastOutput? = null
}
