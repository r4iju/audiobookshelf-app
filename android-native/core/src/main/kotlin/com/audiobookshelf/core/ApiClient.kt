package com.audiobookshelf.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.security.cert.CertPathValidatorException
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.decodeBase64
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private val JsonType = "application/json".toMediaType()

/** Unauthenticated server calls used before an account exists. */
class AuthApi(private val http: OkHttpClient) {
    suspend fun status(address: ServerAddress): ServerStatus =
        AbsJson.decodeFromString(ServerStatus.serializer(), http.execute(Request.Builder().url(address.url("status")).build()))

    suspend fun login(address: ServerAddress, username: String, password: String): Credentials {
        val body = buildJsonObject { put("username", username); put("password", password) }.toString()
        val request = Request.Builder().url(address.url("login")).header("x-return-tokens", "true")
            .post(body.toRequestBody(JsonType)).build()
        val response = try {
            http.execute(request)
        } catch (error: ApiError.Http) {
            if (error.status == 401) throw LoginRejected() else throw error
        }
        return credentialsFrom(address, response)
    }

    class LoginRejected : Exception("The username or password was not accepted.")

    companion object {
        fun credentialsFrom(address: ServerAddress, response: String): Credentials {
            val user = runCatching { AbsJson.decodeFromString(AuthResponse.serializer(), response).user }
                .getOrElse { throw ApiError.InvalidResponse(it) }
            val token = user.bearerToken?.takeIf { it.isNotEmpty() } ?: throw ApiError.SignInRequired()
            return Credentials(address.canonical, user.id, user.username, token, user.refreshToken)
        }
    }
}

/**
 * Account-bound client. Refresh is coordinated so concurrent 401s share one rotation, rotated
 * credentials are persisted through [sink] before use, and transient failures never sign out.
 */
class ApiClient(
    private val http: OkHttpClient,
    initial: Credentials,
    private val sink: CredentialSink,
    val device: DeviceInfo,
) {
    @Volatile var credentials: Credentials = initial
        private set
    val account get() = credentials.account
    val address get() = credentials.address
    private val refreshLock = Mutex()

    // region Catalog
    suspend fun me(): User = get("api/me", User.serializer())
    suspend fun libraries(): List<Library> = get("api/libraries", LibrariesResponse.serializer()).libraries
    suspend fun personalized(libraryId: String): List<PersonalizedShelf> =
        get("api/libraries/$libraryId/personalized", ListSerializer(PersonalizedShelf.serializer()), listOf("minified" to "1", "limit" to "12"))

    suspend fun items(libraryId: String, page: Int, sort: String = "media.metadata.title", descending: Boolean = false, filter: String? = null, limit: Int = 60, collapseSeries: Boolean = false): ItemsPage =
        get("api/libraries/$libraryId/items", ItemsPage.serializer(), buildList {
            add("limit" to "$limit"); add("page" to "$page"); add("sort" to sort); add("desc" to if (descending) "1" else "0"); add("minified" to "1")
            if (collapseSeries) add("collapseseries" to "1")
            filter?.let { add("filter" to it) }
        })

    suspend fun filterData(libraryId: String): FilterData = get("api/libraries/$libraryId/filterdata", FilterData.serializer())
    suspend fun search(libraryId: String, query: String, limit: Int = 12): SearchResponse =
        get("api/libraries/$libraryId/search", SearchResponse.serializer(), listOf("q" to query, "limit" to "$limit"))
    suspend fun item(id: String): LibraryItem = get("api/items/$id", LibraryItem.serializer(), listOf("expanded" to "1", "include" to "progress,rssfeed"))
    suspend fun authors(libraryId: String): List<AuthorResult> = get("api/libraries/$libraryId/authors", AuthorsResponse.serializer()).authors
    suspend fun series(libraryId: String): List<NamedRef> =
        get("api/libraries/$libraryId/series", GroupPage.serializer(NamedRef.serializer()), listOf("minified" to "1", "sort" to "name", "limit" to "10000")).results
    suspend fun author(id: String): AuthorDetail = get("api/authors/$id", AuthorDetail.serializer(), listOf("include" to "items,series"))
    // endregion

    // region Groups
    suspend fun collections(libraryId: String): List<Collection> =
        get("api/libraries/$libraryId/collections", GroupPage.serializer(Collection.serializer())).results
    suspend fun playlists(libraryId: String): List<Playlist> =
        get("api/libraries/$libraryId/playlists", GroupPage.serializer(Playlist.serializer())).results
    suspend fun collection(id: String): Collection = get("api/collections/$id", Collection.serializer())
    suspend fun playlist(id: String): Playlist = get("api/playlists/$id", Playlist.serializer())
    suspend fun createCollection(libraryId: String, name: String, description: String, bookIds: List<String>): Collection =
        send("api/collections", "POST", buildJsonObject { put("libraryId", libraryId); put("name", name); put("description", description); putJsonArray("books") { bookIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } } }, Collection.serializer())
    suspend fun updateCollection(id: String, name: String, description: String, bookIds: List<String>): Collection =
        send("api/collections/$id", "PATCH", buildJsonObject { put("name", name); put("description", description); putJsonArray("books") { bookIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } } }, Collection.serializer())
    suspend fun collectionMembership(id: String, add: Boolean, bookIds: List<String>) {
        raw("api/collections/$id/batch/${if (add) "add" else "remove"}", "POST", buildJsonObject { putJsonArray("books") { bookIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } } })
    }
    suspend fun createPlaylist(libraryId: String, name: String, description: String, members: List<Pair<String, String?>>): Playlist =
        send("api/playlists", "POST", buildJsonObject { put("libraryId", libraryId); put("name", name); put("description", description); putMembers(members) }, Playlist.serializer())
    suspend fun updatePlaylist(id: String, name: String, description: String, members: List<Pair<String, String?>>): Playlist =
        send("api/playlists/$id", "PATCH", buildJsonObject { put("name", name); put("description", description); putMembers(members) }, Playlist.serializer())
    suspend fun playlistMembership(id: String, add: Boolean, members: List<Pair<String, String?>>) {
        raw("api/playlists/$id/batch/${if (add) "add" else "remove"}", "POST", buildJsonObject { putMembers(members) })
    }
    suspend fun deleteGroup(kind: String, id: String) { raw("api/$kind/$id", "DELETE", null) }

    private fun kotlinx.serialization.json.JsonObjectBuilder.putMembers(members: List<Pair<String, String?>>) =
        putJsonArray("items") { members.forEach { (item, episode) -> add(buildJsonObject { put("libraryItemId", item); episode?.let { put("episodeId", it) } }) } }
    // endregion

    // region Playback and progress
    /** Opens a server stream session; [transcode] requests HLS when direct play of the files failed. */
    suspend fun play(itemId: String, episodeId: String?, transcode: Boolean = false): PlaybackSession {
        val path = "api/items/$itemId/play" + (episodeId?.let { "/$it" } ?: "")
        val session = send(path, "POST", buildJsonObject {
            put("forceDirectPlay", !transcode); put("forceTranscode", transcode); put("mediaPlayer", "exo-player")
            put("deviceInfo", AbsJson.encodeToJsonElement(DeviceInfo.serializer(), device))
        }, PlaybackSession.serializer())
        if (session.audioTracks.isEmpty()) throw ApiError.NoAudio()
        return session
    }

    /** Ordinary stream sessions close with an empty body; listening is published separately through [syncLocal]. */
    /**
     * Closing is idempotent: a session the server already closed answers 404. So a close whose connection
     * dropped, as a pooled connection the server is closing as idle does, is sent once more with the same
     * token. Only the close itself: a lost token refresh is not repeated, because the server already
     * replaced the refresh token it was sent.
     */
    suspend fun closeSession(sessionId: String) {
        try {
            execute("api/session/$sessionId/close", "POST", emptyList(), JsonObject(emptyMap()), resendWhenDropped = true)
        } catch (error: ApiError.Http) {
            if (error.status != 404) throw error
        }
    }

    /**
     * Publishes absolute listening totals for a stable session ID. The server treats a repeated ID
     * as the same session, so an ambiguous acknowledgment can be retried without double counting.
     */
    suspend fun syncLocal(sessions: List<JsonObject>): Set<String> {
        val response = raw("api/session/local-all", "POST", buildJsonObject {
            putJsonArray("sessions") { sessions.forEach { add(it) } }
            put("deviceInfo", AbsJson.encodeToJsonElement(DeviceInfo.serializer(), device))
        })
        val results = runCatching { AbsJson.decodeFromString(LocalSyncResponse.serializer(), response).results }.getOrElse { throw ApiError.InvalidResponse(it) }
        return results.filter { it.success }.map { it.id }.toSet()
    }

    suspend fun setFinished(itemId: String, episodeId: String?, finished: Boolean): MediaProgress? {
        val response = raw("api/me/progress/$itemId" + (episodeId?.let { "/$it" } ?: ""), "PATCH", buildJsonObject { put("isFinished", finished) })
        return runCatching { AbsJson.decodeFromString(MediaProgress.serializer(), response) }.getOrNull()
    }

    /** The signed-in user together with what the server lets them do, such as the e-readers they may send to. */
    suspend fun authorize(): AuthResponse = send("api/authorize", "POST", null, AuthResponse.serializer())

    suspend fun sendEbook(itemId: String, deviceName: String) {
        raw("api/emails/send-ebook-to-device", "POST", buildJsonObject { put("libraryItemId", itemId); put("deviceName", deviceName) })
    }

    suspend fun openFeed(itemId: String, slug: String, meta: RssFeedMeta): RssFeed =
        send("api/feeds/item/$itemId/open", "POST", buildJsonObject {
            put("serverAddress", address.canonical)
            put("slug", slug)
            put("metadataDetails", AbsJson.encodeToJsonElement(RssFeedMeta.serializer(), meta))
        }, FeedResponse.serializer()).feed

    suspend fun closeFeed(feedId: String) { raw("api/feeds/$feedId/close", "POST", null) }

    /** Feed URLs are relative to the server address the feed was opened with. */
    fun feedUrl(feed: RssFeed): String =
        if (feed.feedUrl.startsWith("/")) address.canonical.trimEnd('/') + feed.feedUrl else feed.feedUrl

    suspend fun removeProgress(progressId: String) { raw("api/me/progress/$progressId", "DELETE", null) }

    /** The account's progress for one item, or null when the server has none. */
    suspend fun progress(itemId: String, episodeId: String?): MediaProgress? = try {
        get("api/me/progress/$itemId" + (episodeId?.let { "/$it" } ?: ""), MediaProgress.serializer())
    } catch (error: ApiError.Http) {
        if (error.status == 404) null else throw error
    }

    suspend fun saveEbookProgress(itemId: String, location: String, progress: Double) {
        raw("api/me/progress/$itemId", "PATCH", buildJsonObject { put("ebookLocation", location); put("ebookProgress", progress) })
    }

    suspend fun saveBookmark(itemId: String, time: Double, title: String, editing: Boolean): Bookmark =
        send("api/me/item/$itemId/bookmark", if (editing) "PATCH" else "POST", buildJsonObject { put("time", time); put("title", title) }, Bookmark.serializer())
    suspend fun deleteBookmark(itemId: String, time: Double) { raw("api/me/item/$itemId/bookmark/${formatTime(time)}", "DELETE", null) }
    suspend fun listeningStats(): ListeningStats = get("api/me/listening-stats", ListeningStats.serializer())
    // endregion

    // region Podcasts
    suspend fun discoverPodcasts(term: String): List<PodcastDiscovery> =
        get("api/search/podcast", ListSerializer(PodcastDiscovery.serializer()), listOf("term" to term))
    suspend fun podcastFeed(url: String): JsonObject =
        AbsJson.decodeFromString(JsonObject.serializer(), raw("api/podcasts/feed", "POST", buildJsonObject { put("rssFeed", url) }))
    suspend fun createPodcast(body: JsonObject): LibraryItem = send("api/podcasts", "POST", body, LibraryItem.serializer())
    suspend fun downloadFeedEpisodes(itemId: String, episodes: List<JsonElement>) {
        raw("api/podcasts/$itemId/download-episodes", "POST", kotlinx.serialization.json.JsonArray(episodes))
    }
    // endregion

    /** Authorization header for media, cover and download requests; refreshed when close to expiry. */
    suspend fun bearer(): String {
        val current = credentials
        if (current.refreshToken != null && jwtExpiresSoon(current.accessToken)) refresh(current)
        return credentials.accessToken
    }

    /** Refreshes after another channel, such as the realtime socket, rejected [token]; returns the token to retry with. */
    suspend fun bearerAfterRejection(token: String): String {
        val current = credentials
        if (current.accessToken == token) refresh(current)
        return credentials.accessToken
    }

    suspend fun bytes(path: String): ByteArray = authorized(path) { token ->
        http.executeBytes(Request.Builder().url(address.url(path)).header("Authorization", "Bearer $token").build())
    }

    fun mediaUrl(path: String): HttpUrl = address.mediaUrl(path)
    fun owns(url: HttpUrl): Boolean = address.contains(url)
    fun coverUrl(itemId: String, width: Int = 400): HttpUrl = address.url("api/items/$itemId/cover", listOf("width" to "$width", "format" to "jpeg"))

    private suspend fun <T> get(path: String, serializer: KSerializer<T>, query: List<Pair<String, String>> = emptyList()): T =
        decode(execute(path, "GET", query, null), serializer)

    private suspend fun <T> send(path: String, method: String, body: JsonElement?, serializer: KSerializer<T>): T =
        decode(execute(path, method, emptyList(), body), serializer)

    private suspend fun raw(path: String, method: String, body: JsonElement?): String = execute(path, method, emptyList(), body)

    private fun <T> decode(value: String, serializer: KSerializer<T>): T =
        runCatching { AbsJson.decodeFromString(serializer, value) }.getOrElse { throw ApiError.InvalidResponse(it) }

    private suspend fun execute(path: String, method: String, query: List<Pair<String, String>>, body: JsonElement?, resendWhenDropped: Boolean = false): String =
        authorized(path) { token ->
            val payload = body?.toString()?.toRequestBody(JsonType)
            val request = Request.Builder().url(address.url(path, query)).header("Authorization", "Bearer $token")
                .method(method, payload ?: if (method == "GET" || method == "DELETE") null else ByteArray(0).toRequestBody(JsonType)).build()
            val client = if (method == "GET") http else writes
            try { client.execute(request) } catch (dropped: ApiError.Offline) { if (resendWhenDropped) client.execute(request) else throw dropped }
        }

    /**
     * OkHttp sends a request again by itself when a reused connection fails, even after the request
     * was written. For a write that hides a lost answer while the server may still apply the original.
     */
    private val writes by lazy { http.newBuilder().retryOnConnectionFailure(false).build() }

    private suspend fun <T> authorized(path: String, call: suspend (String) -> T): T {
        val used = bearer()
        try {
            return call(used)
        } catch (error: ApiError.Http) {
            if (error.status != 401) throw error
        }
        val current = credentials
        if (current.refreshToken == null) throw ApiError.SignInRequired(account, used)
        // A refresh completed by a concurrent request also satisfies this older 401.
        if (current.accessToken == used) refresh(current)
        val retried = credentials.accessToken
        try {
            return call(retried)
        } catch (error: ApiError.Http) {
            if (error.status == 401) throw ApiError.SignInRequired(account, retried)
            throw error
        }
    }

    private suspend fun refresh(seen: Credentials) {
        refreshLock.lock()
        try {
            val current = credentials
            if (current.accessToken != seen.accessToken) return
            val token = current.refreshToken ?: throw ApiError.SignInRequired(account, current.accessToken)
            val request = Request.Builder().url(address.url("auth/refresh")).header("x-refresh-token", token)
                .post(ByteArray(0).toRequestBody(JsonType)).build()
            val response = try {
                http.execute(request)
            } catch (error: ApiError.Http) {
                if (error.status == 401 || error.status == 403) throw ApiError.SignInRequired(account, current.accessToken)
                throw error
            }
            val user = runCatching { AbsJson.decodeFromString(AuthResponse.serializer(), response).user }.getOrElse { throw ApiError.InvalidResponse(it) }
            val bearer = user.bearerToken?.takeIf { it.isNotEmpty() } ?: throw ApiError.SignInRequired(account, current.accessToken)
            if (user.id != current.userId) throw ApiError.SignInRequired(account, current.accessToken)
            val next = current.copy(accessToken = bearer, refreshToken = user.refreshToken ?: token, username = user.username.ifEmpty { current.username })
            sink.rotated(current, next)
            credentials = next
        } finally {
            refreshLock.unlock()
        }
    }

    @kotlinx.serialization.Serializable private data class FeedResponse(val feed: RssFeed)
    @kotlinx.serialization.Serializable private data class LocalSyncResult(val id: String, val success: Boolean = false)
    @kotlinx.serialization.Serializable private data class LocalSyncResponse(val results: List<LocalSyncResult> = emptyList())

    companion object {
        /** Library filter value as the server expects it: `group.base64(value)`. */
        fun filter(group: String, value: String): String = "$group." + value.encodeUtf8().base64()
        fun formatTime(time: Double): String = if (time == Math.floor(time)) time.toLong().toString() else time.toString()
    }
}

internal suspend fun OkHttpClient.execute(request: Request): String = executeBytes(request).decodeToString()

internal suspend fun OkHttpClient.executeBytes(request: Request): ByteArray = withContext(Dispatchers.IO) {
    val response = try { newCall(request).await() } catch (error: IOException) { throw classify(error) }
    response.use {
        if (!it.isSuccessful) throw ApiError.Http(it.code, runCatching { it.body?.string()?.take(512) }.getOrNull())
        try { it.body?.bytes() ?: ByteArray(0) } catch (error: IOException) { throw classify(error) }
    }
}

fun classify(error: Throwable): ApiError {
    var cause: Throwable? = error
    while (cause != null) {
        if (cause is SSLHandshakeException || cause is SSLPeerUnverifiedException || cause is CertPathValidatorException) return ApiError.Untrusted(error)
        cause = cause.cause
    }
    return ApiError.Offline(error)
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) { if (continuation.isActive) continuation.resumeWithException(e) }
        override fun onResponse(call: Call, response: Response) { continuation.resume(response) }
    })
}

internal fun jwtExpiresSoon(token: String, nowSeconds: Long = System.currentTimeMillis() / 1000): Boolean {
    val parts = token.split('.')
    if (parts.size != 3) return false
    val payload = parts[1].decodeBase64()?.utf8() ?: return false
    val expiry = Regex("\"exp\"\\s*:\\s*([0-9]+)").find(payload)?.groupValues?.get(1)?.toLongOrNull() ?: return false
    return expiry < nowSeconds + 60
}
