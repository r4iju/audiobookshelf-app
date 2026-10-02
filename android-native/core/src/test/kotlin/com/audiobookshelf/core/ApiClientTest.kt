package com.audiobookshelf.core

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

class ApiClientTest {
    private val server = MockWebServer()
    private val refreshes = AtomicInteger()
    private val rotations = CopyOnWriteArrayList<Credentials>()
    private var refreshStatus = 200

    private fun start(): ApiClient {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.path == "/abs/auth/refresh") {
                    refreshes.incrementAndGet()
                    Thread.sleep(150)
                    if (refreshStatus != 200) return MockResponse().setResponseCode(refreshStatus)
                    return MockResponse().setBody("""{"user":{"id":"u1","username":"qa","accessToken":"fresh","refreshToken":"refresh-2"}}""")
                }
                if (request.getHeader("Authorization") != "Bearer fresh") return MockResponse().setResponseCode(401)
                return MockResponse().setBody("""{"libraries":[{"id":"books","name":"Audiobooks","mediaType":"book"}]}""")
            }
        }
        server.start()
        val address = ServerAddress.parse(server.url("/abs").toString())
        val credentials = Credentials(address.canonical, "u1", "qa", "expired", "refresh")
        return ApiClient(OkHttpClient(), credentials, { _, next -> rotations += next }, DeviceInfo("device"))
    }

    @After fun stop() = server.shutdown()

    @Test
    fun concurrentRejectedRequestsShareOneRefreshAndPersistTheRotation() = runBlocking {
        val client = start()
        val results = (1..4).map { async { client.libraries() } }.awaitAll()
        assertTrue(results.all { it.single().id == "books" })
        assertEquals(1, refreshes.get())
        assertEquals("fresh", client.credentials.accessToken)
        assertEquals(listOf("refresh-2"), rotations.map { it.refreshToken })
    }

    @Test
    fun temporaryRefreshFailureKeepsTheAccount() = runBlocking {
        refreshStatus = 503
        val client = start()
        val failure = runCatching { client.libraries() }.exceptionOrNull()
        assertTrue("$failure", failure is ApiError.Http && failure.status == 503)
        assertEquals("refresh", client.credentials.refreshToken)
        assertTrue(rotations.isEmpty())
    }

    @Test
    fun rejectedRefreshRequiresSignIn() = runBlocking {
        refreshStatus = 401
        val client = start()
        assertTrue(runCatching { client.libraries() }.exceptionOrNull() is ApiError.SignInRequired)
    }

    @Test
    fun rejectionNamesTheAccountAndCredentialsItCameFrom() = runBlocking {
        refreshStatus = 401
        val client = start()
        val failure = runCatching { client.libraries() }.exceptionOrNull() as ApiError.SignInRequired
        assertEquals(client.account, failure.account)
        assertEquals("expired", failure.rejectedToken)
    }

    @Test
    fun unreachableServerIsOfflineNotSignedOut() = runBlocking {
        val client = start()
        server.shutdown()
        val failure = runCatching { client.libraries() }.exceptionOrNull()
        assertTrue("$failure", failure is ApiError.Offline)
    }

    @Test
    fun aWriteWhoseConnectionDropsIsNotSentAgainBehindTheCallersBack() = runBlocking {
        val writes = AtomicInteger()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.method == "GET") return MockResponse().setBody("""{"libraries":[]}""")
                // The first write is received, then its connection drops before any answer.
                return if (writes.incrementAndGet() == 1) MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST)
                else MockResponse().setBody("""{"results":[{"id":"s1","success":true}]}""")
            }
        }
        server.start()
        val address = ServerAddress.parse(server.url("/abs").toString())
        val client = ApiClient(OkHttpClient(), Credentials(address.canonical, "u1", "qa", "fresh", "refresh"), { _, _ -> }, DeviceInfo("device"))
        client.libraries()
        val outcome = runCatching { client.syncLocal(listOf(kotlinx.serialization.json.buildJsonObject { put("id", kotlinx.serialization.json.JsonPrimitive("s1")) })) }
        assertTrue("The caller must learn that the answer was lost, got $outcome", outcome.isFailure)
        assertEquals("Sent once; the server may still apply it", 1, writes.get())
    }

    @Test
    fun closingASessionIsSentAgainWhenItsConnectionDrops() = runBlocking {
        val closes = AtomicInteger()
        val sent = CopyOnWriteArrayList<String>()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.method == "GET") return MockResponse().setBody("""{"libraries":[]}""")
                sent += "${request.method} ${request.path} ${request.getHeader("Authorization")} ${request.body.readUtf8()}"
                // A pooled connection the server is closing as idle drops the first close.
                return if (closes.incrementAndGet() == 1) MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST)
                else MockResponse().setResponseCode(404)
            }
        }
        server.start()
        val address = ServerAddress.parse(server.url("/abs").toString())
        val client = ApiClient(OkHttpClient(), Credentials(address.canonical, "u1", "qa", "fresh", "refresh"), { _, _ -> }, DeviceInfo("device"))
        client.libraries()
        val outcome = runCatching { client.closeSession("s1") }
        assertTrue("A dropped close is sent again, and a session the first attempt closed counts as closed, got $outcome", outcome.isSuccess)
        assertEquals(List(2) { "POST /abs/api/session/s1/close Bearer fresh {}" }, sent)
    }

    @Test
    fun aCloseWhoseTokenRefreshLosesItsAnswerDoesNotRefreshAgain() = runBlocking {
        val refreshes = AtomicInteger()
        val closes = AtomicInteger()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.path == "/abs/auth/refresh") {
                    // The server rotates the refresh token before answering; the answer is lost.
                    refreshes.incrementAndGet()
                    return MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST)
                }
                closes.incrementAndGet()
                return MockResponse().setResponseCode(200)
            }
        }
        server.start()
        val address = ServerAddress.parse(server.url("/abs").toString())
        val expired = "e30.${with(okio.ByteString) { """{"exp":1}""".encodeUtf8() }.base64Url().trimEnd('=')}.signature"
        val client = ApiClient(OkHttpClient(), Credentials(address.canonical, "u1", "qa", expired, "refresh"), { _, _ -> }, DeviceInfo("device"))
        val outcome = runCatching { client.closeSession("s1") }
        assertTrue("A lost refresh answer is Offline, not a sign-in, got $outcome", outcome.exceptionOrNull() is ApiError.Offline)
        assertEquals("The spent refresh token is not sent again", 1, refreshes.get())
        assertEquals("No close was sent with the expired token", 0, closes.get())
    }

    @Test
    fun aWriteIsNotSentOnAConnectionTheServerClosedWhileIdle() = runBlocking {
        val writes = AtomicInteger()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                // The server answers, keeps the connection open for reuse, then closes it as idle.
                if (request.method == "GET") return MockResponse().setBody("""{"libraries":[]}""").setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AT_END)
                writes.incrementAndGet()
                return MockResponse().setBody("""{"results":[{"id":"s1","success":true}]}""")
            }
        }
        server.start()
        val address = ServerAddress.parse(server.url("/abs").toString())
        val client = ApiClient(OkHttpClient(), Credentials(address.canonical, "u1", "qa", "fresh", "refresh"), { _, _ -> }, DeviceInfo("device"))
        client.libraries()
        Thread.sleep(500)
        val outcome = runCatching { client.syncLocal(listOf(kotlinx.serialization.json.buildJsonObject { put("id", kotlinx.serialization.json.JsonPrimitive("s1")) })) }
        assertEquals("The write reaches the server on a live connection, got $outcome", setOf("s1"), outcome.getOrNull())
        assertEquals(1, writes.get())
    }

    @Test
    fun aWriteReachesTheServerWhenItsFirstAddressRefusesTheConnection() = runBlocking {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = MockResponse().setBody("""{"results":[{"id":"s1","success":true}]}""")
        }
        server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
        // A dual-stack host whose IPv6 address does not answer; nothing is sent before the connection is made.
        val dns = object : okhttp3.Dns {
            override fun lookup(hostname: String) = listOf(java.net.InetAddress.getByName("::1"), java.net.InetAddress.getByName("127.0.0.1"))
        }
        val address = ServerAddress.parse("http://books.test:${server.port}/abs")
        val client = ApiClient(OkHttpClient.Builder().dns(dns).build(), Credentials(address.canonical, "u1", "qa", "fresh", "refresh"), { _, _ -> }, DeviceInfo("device"))
        val outcome = runCatching { client.syncLocal(listOf(kotlinx.serialization.json.buildJsonObject { put("id", kotlinx.serialization.json.JsonPrimitive("s1")) })) }
        assertEquals("The write is sent once over the address that answers, got $outcome", setOf("s1"), outcome.getOrNull())
        assertEquals(1, server.requestCount)
    }
}
