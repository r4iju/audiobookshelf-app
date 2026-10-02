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
}
