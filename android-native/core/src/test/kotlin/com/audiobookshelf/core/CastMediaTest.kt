package com.audiobookshelf.core

import org.junit.Assert.assertEquals
import org.junit.Test

class CastMediaTest {
    private val address = ServerAddress.parse("https://books.example.lan/abs")
    private val track = AudioTrack(index = 2, contentUrl = "/api/items/li_1/file/77", mimeType = "audio/mpeg")

    @Test
    fun aReceiverFetchesDirectPlayTracksThroughThePublicSessionRouteFromServer2_22() {
        for (version in listOf("2.22.0", "2.30.0", "2.30.0-fixture", "3.0.1")) {
            assertEquals(version, "https://books.example.lan/abs/public/session/ps_9/track/2",
                castTrackUrl(address, version, "ps_9", track, transcoded = false, token = "secret").toString())
        }
    }

    @Test
    fun transcodedTracksUseTheServerStreamWithoutAToken() {
        val hls = AudioTrack(index = 1, contentUrl = "/hls/ps_9/output.m3u8", mimeType = "application/vnd.apple.mpegurl")
        assertEquals("https://books.example.lan/abs/hls/ps_9/output.m3u8",
            castTrackUrl(address, "2.30.0", "ps_9", hls, transcoded = true, token = "secret").toString())
    }

    @Test
    fun olderServersReceiveTheTrackWithTheTokenTheReceiverCannotSendAsAHeader() {
        for (version in listOf("2.21.9", "2.9.0", null)) {
            assertEquals("$version", "https://books.example.lan/abs/api/items/li_1/file/77?token=secret",
                castTrackUrl(address, version, "ps_9", track, transcoded = false, token = "secret").toString())
        }
    }
}
