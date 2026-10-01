package com.audiobookshelf.android.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.audiobookshelf.android.BuildConfig
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.AuthApi
import com.audiobookshelf.core.ServerAddress
import com.audiobookshelf.core.ServerStatus
import com.audiobookshelf.core.await
import com.audiobookshelf.core.classify
import com.audiobookshelf.core.writeAtomically
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import okio.ByteString.Companion.toByteString

/**
 * Browser sign-in against the server's existing mobile OpenID contract (PKCE, state validation,
 * server session cookie carried from authorization to exchange). The pending flow is persisted so
 * a callback still completes if Android reclaims the app while the browser is in front.
 */
class OpenIdSignIn private constructor(private val context: Context) {
    @Serializable private data class Pending(val server: String, val verifier: String, val state: String, val cookies: List<String>)

    var error by mutableStateOf<String?>(null)
        private set
    var busy by mutableStateOf(false)
        private set
    private var browserOpen = false
    private val file get() = File(context.noBackupFilesDir, "openid-pending.json")
    private val graph get() = context.graph
    private val transport by lazy { graph.http.newBuilder().followRedirects(false).followSslRedirects(false).build() }

    fun start(address: ServerAddress) {
        error = null; busy = true
        graph.scope.launch {
            try {
                val status = AbsJson.decodeFromString(ServerStatus.serializer(), get(address.url("status")).body)
                if ("openid" !in status.authMethods) throw Failure("OpenID sign-in is not enabled on this server. Use your username and password.")
                val verifier = random(); val state = random()
                val challenge = base64Url(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
                val authorize = get(address.url("auth/openid", listOf(
                    "code_challenge" to challenge, "code_challenge_method" to "S256", "state" to state,
                    "redirect_uri" to BuildConfig.OAUTH_REDIRECT, "client_id" to "Audiobookshelf-App", "response_type" to "code",
                )))
                if (authorize.code !in 300..399) {
                    if (authorize.code >= 400) throw ApiError.Http(authorize.code)
                    throw Failure(INVALID)
                }
                val provider = authorize.location?.let { address.url("").resolve(it) } ?: throw Failure(INVALID)
                validateProvider(provider)
                val providerState = provider.single("state")
                if (providerState != state || provider.single("code_challenge") != challenge || provider.single("code_challenge_method") != "S256") throw Failure(INVALID)
                writeAtomically(file, AbsJson.encodeToString(Pending.serializer(), Pending(address.canonical, verifier, providerState, authorize.cookies)).toByteArray())
                browserOpen = true
                CustomTabsIntent.Builder().setShowTitle(true).setEphemeralBrowsingEnabled(true).build().apply {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }.launchUrl(context, Uri.parse(provider.toString()))
            } catch (failure: Exception) {
                error = failure.message
                busy = false
            }
        }
    }

    /** Handles `audiobookshelf-native-preview://oauth?...`; returns true when the intent was a callback. */
    fun handle(intent: Intent?): Boolean {
        val uri = intent?.data ?: return false
        if ("${uri.scheme}://${uri.host}" != BuildConfig.OAUTH_REDIRECT) return false
        browserOpen = false
        val pending = runCatching { AbsJson.decodeFromString(Pending.serializer(), file.readText()) }.getOrNull()
        file.delete()
        if (pending == null) { error = INVALID; busy = false; return true }
        busy = true; error = null
        graph.scope.launch {
            try {
                val states = uri.getQueryParameters("state"); val codes = uri.getQueryParameters("code")
                if (uri.path?.isNotEmpty() == true || uri.port != -1 || uri.fragment != null || states != listOf(pending.state) || codes.size != 1 || codes[0].isEmpty()) throw Failure(INVALID)
                val address = ServerAddress.parse(pending.server)
                val request = Request.Builder().url(address.url("auth/openid/callback", listOf("state" to pending.state, "code" to codes[0], "code_verifier" to pending.verifier)))
                    .header("x-return-tokens", "true").apply { if (pending.cookies.isNotEmpty()) header("Cookie", pending.cookies.joinToString("; ")) }.build()
                val response = execute(request)
                if (response.code != 200) throw ApiError.Http(response.code)
                graph.accounts.adopt(AuthApi.credentialsFrom(address, response.body))
            } catch (failure: Exception) {
                error = failure.message
            } finally { busy = false }
        }
        return true
    }

    /** Called when the app returns to the foreground; no callback means the user left the browser. */
    fun resumed() {
        if (browserOpen) {
            browserOpen = false
            file.delete()
            busy = false
            error = "Browser sign-in was canceled. Your saved accounts are retained."
        }
    }

    private data class Reply(val code: Int, val body: String, val location: String?, val cookies: List<String>)

    private suspend fun get(url: HttpUrl) = execute(Request.Builder().url(url).build())

    private suspend fun execute(request: Request): Reply = try {
        withContext(Dispatchers.IO) { transport.newCall(request).await().use { response ->
            Reply(response.code, response.body?.string().orEmpty(), response.header("Location"), response.headers("Set-Cookie").map { it.substringBefore(';') })
        } }
    } catch (failure: IOException) { throw classify(failure) }

    private fun validateProvider(url: HttpUrl) {
        val loopback = url.host in setOf("127.0.0.1", "localhost", "::1")
        if (url.username.isNotEmpty() || url.password.isNotEmpty() || url.fragment != null || !(url.isHttps || loopback)) throw Failure(INVALID)
        url.single("client_id"); url.single("redirect_uri")
        if ("openid" !in url.single("scope").split(' ')) throw Failure(INVALID)
    }

    private fun HttpUrl.single(name: String): String = queryParameterValues(name).singleOrNull()?.takeIf { it.isNotEmpty() } ?: throw Failure(INVALID)

    private class Failure(message: String) : Exception(message)

    companion object {
        private const val INVALID = "The browser sign-in response could not be verified. Retry sign-in and check the server's OpenID redirect settings."
        @Volatile private var instance: OpenIdSignIn? = null
        fun pending(context: Context): OpenIdSignIn = instance ?: synchronized(this) {
            instance ?: OpenIdSignIn(context.applicationContext).also { instance = it }
        }
        private fun random() = base64Url(ByteArray(32).also { SecureRandom().nextBytes(it) })
        private fun base64Url(bytes: ByteArray) = bytes.toByteString().base64Url().trimEnd('=')
        @Suppress("unused") private fun String.toUrl() = toHttpUrlOrNull()
    }
}
