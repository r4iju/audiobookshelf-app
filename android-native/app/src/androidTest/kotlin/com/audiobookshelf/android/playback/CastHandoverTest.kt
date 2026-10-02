package com.audiobookshelf.android.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** A downloaded title playing on the phone when a receiver connects, with no receiver needed. */
@RunWith(AndroidJUnit4::class)
class CastHandoverTest {
    /** The order Media3 1.9 `CastPlayerImpl.updateActivePlayer` follows; the callback cannot stop the switch. */
    private fun switch(handover: CastHandover, from: Player, to: Player) {
        handover.transfer(from, to)
        if (to.playbackState == Player.STATE_IDLE) to.prepare()
        from.stop()
    }

    @Test
    fun aDownloadStaysOnThePhoneAtItsPositionAndTheReceiverSessionIsEnded() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val phone = ExoPlayer.Builder(context).build()
            val receiver = ExoPlayer.Builder(context).build()
            phone.setMediaItems(listOf(MediaItem.fromUri("file:///offline/part-1.m4b"), MediaItem.fromUri("file:///offline/part-2.m4b")), 1, 4_000)
            phone.playWhenReady = true
            var ended = 0
            val notices = mutableListOf<String>()
            val handover = CastHandover(phone, endSession = { ended++ }, explain = { notices += it })

            switch(handover, phone, receiver)
            switch(handover, receiver, phone)

            try {
                assertEquals("The phone keeps the downloaded parts", 2, phone.mediaItemCount)
                assertEquals(1, phone.currentMediaItemIndex)
                assertEquals(4_000, phone.currentPosition)
                assertTrue("The phone resumes playing", phone.playWhenReady)
                assertEquals("Nothing is sent to the receiver", 0, receiver.mediaItemCount)
                assertEquals("The receiver session is ended", 1, ended)
                assertEquals(listOf(CastHandover.DOWNLOAD_NOT_CASTABLE), notices)
            } finally {
                phone.release(); receiver.release()
            }
        }
    }
}
