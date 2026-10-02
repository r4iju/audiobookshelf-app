package com.audiobookshelf.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ServerAddressTest {
    @Test
    fun keepsReverseProxySubpathForApiAndMediaRequests() {
        val address = ServerAddress.parse("  HTTPS://Books.Example.LAN:443/abs/ ")
        assertEquals("https://books.example.lan/abs", address.canonical)
        assertEquals("https://books.example.lan/abs/api/libraries?limit=60", address.url("/api/libraries", listOf("limit" to "60")).toString())
        assertEquals("https://books.example.lan/abs/audio/0", address.mediaUrl("/audio/0").toString())
        assertEquals("https://books.example.lan/abs/api/items/a/file/1?token=x", address.mediaUrl("/api/items/a/file/1?token=x").toString())
    }

    @Test
    fun rejectsAddressesAndMediaThatWouldLeaveTheServer() {
        for (raw in listOf("ftp://host", "books.lan", "http://user:pw@host", "http://host/?q=1", "http://host/#x", "")) {
            assertThrows(raw, ApiError.InvalidServer::class.java) { ServerAddress.parse(raw) }
        }
        val address = ServerAddress.parse("http://127.0.0.1:28765/abs")
        for (path in listOf("//evil.example/a", "http://evil.example/a", "http://127.0.0.1:9/abs/a", "https://127.0.0.1:28765/abs/a")) {
            assertThrows(path, ApiError.UnsafeMediaUrl::class.java) { address.mediaUrl(path) }
        }
        assertEquals("http://127.0.0.1:28765/abs/audio/1", address.mediaUrl("http://127.0.0.1:28765/abs/audio/1").toString())
    }
}
