package com.audiobookshelf.android.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** A downloaded title playing on the phone when a receiver connects, with no receiver needed. */
@RunWith(AndroidJUnit4::class)
class CastHandoverTest {
    /** The order Media3 1.9 `CastPlayerImpl.updateActivePlayer` follows; the callback cannot stop the switch. */
    private fun switch(handover: CastHandover, from: Player, to: Player) {
        handover.transfer(from, to)
        if (from.playbackState != Player.STATE_IDLE) to.prepare()
        from.stop()
    }

    private fun playDownload(phone: ExoPlayer) {
        phone.setMediaItems(listOf(MediaItem.fromUri("file:///offline/part-1.m4b"), MediaItem.fromUri("file:///offline/part-2.m4b")), 1, 4_000)
        phone.prepare()
        phone.playWhenReady = true
    }

    /** The receiver had nothing to play; once its session ends it is idle, as a real `RemoteCastPlayer` is. */
    private fun sessionEnds(receiver: Player) {
        receiver.stop()
        receiver.clearMediaItems()
    }

    @Test
    fun aDownloadClosedWhileTheReceiverSessionEndsIsNotResumedOnThePhone() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val phone = ExoPlayer.Builder(context).build()
            val receiver = ExoPlayer.Builder(context).build()
            playDownload(phone)
            var title: Any? = Any()
            val handover = CastHandover(phone, endSession = {}, explain = {}, title = { title })

            try {
                switch(handover, phone, receiver)
                // Closing, or switching account, while the disconnect is pending acts on the active player, the receiver.
                title = null
                sessionEnds(receiver)
                switch(handover, receiver, phone)
                assertEquals("The closed title's parts are cleared from the phone", 0, phone.mediaItemCount)
                assertFalse("The phone does not start playing", phone.playWhenReady)
            } finally {
                phone.release(); receiver.release()
            }
        }
    }

    @Test
    fun aDownloadPausedWhileTheReceiverSessionEndsStaysPausedOnThePhone() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val phone = ExoPlayer.Builder(context).build()
            val receiver = ExoPlayer.Builder(context).build()
            playDownload(phone)
            val title = Any()
            val handover = CastHandover(phone, endSession = {}, explain = {}, title = { title })

            try {
                switch(handover, phone, receiver)
                handover.pause()
                sessionEnds(receiver)
                switch(handover, receiver, phone)
                assertEquals(2, phone.mediaItemCount)
                assertEquals(4_000, phone.currentPosition)
                assertFalse("The listener's pause holds", phone.playWhenReady)
            } finally {
                phone.release(); receiver.release()
            }
        }
    }

    @Test
    fun aDownloadStaysOnThePhoneAtItsPositionAndTheReceiverSessionIsEnded() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val phone = ExoPlayer.Builder(context).build()
            val receiver = ExoPlayer.Builder(context).build()
            playDownload(phone)
            var ended = 0
            val notices = mutableListOf<Int>()
            val title = Any()
            val handover = CastHandover(phone, endSession = { ended++ }, explain = { notices += it }, title = { title })

            switch(handover, phone, receiver)
            sessionEnds(receiver)
            switch(handover, receiver, phone)

            try {
                assertEquals("The phone keeps the downloaded parts", 2, phone.mediaItemCount)
                assertEquals(1, phone.currentMediaItemIndex)
                assertEquals(4_000, phone.currentPosition)
                assertTrue("The phone resumes playing", phone.playWhenReady)
                assertTrue("The phone is prepared again, not left stopped", phone.playbackState != Player.STATE_IDLE)
                assertEquals("Nothing is sent to the receiver", 0, receiver.mediaItemCount)
                assertEquals("The receiver session is ended", 1, ended)
                assertEquals(listOf(CastHandover.DOWNLOAD_NOT_CASTABLE), notices)
            } finally {
                phone.release(); receiver.release()
            }
        }
    }

    @Test
    fun aReceiverQueueFromBeforeTheAppRestartedIsNeitherKeptNorCopiedToThePhone() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val phone = ExoPlayer.Builder(context).build()
            val receiver = ExoPlayer.Builder(context).build()
            // Left playing on the receiver by the process that died; this process opened no title.
            receiver.setMediaItems(listOf(MediaItem.fromUri("https://server.invalid/public/session/old/track/0")), 0, 9_000)
            receiver.playWhenReady = true
            val handover = CastHandover(phone, endSession = {}, explain = {}, title = { null })

            try {
                switch(handover, receiver, phone)
                assertEquals("Nothing from the receiver reaches the phone", 0, phone.mediaItemCount)
                assertFalse("The phone does not start playing", phone.playWhenReady)
            } finally {
                phone.release(); receiver.release()
            }
        }
    }

    @Test
    fun aSessionResumedAfterTheAppRestartedWithNoTitleOpenIsEndedWithAnExplanation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val routes = CastRoutes(instrumentation.targetContext)
            assertEquals("Play services provides casting on the QA emulator", null, routes.status.value.unavailable)
            routes.keepResumed = { false }
            routes.resumed()
            assertEquals(InstrumentationRegistry.getInstrumentation().targetContext.getString(CastRoutes.RESUMED_WITHOUT_TITLE), routes.status.value.problem)
        }
    }
}
