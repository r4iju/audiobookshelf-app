package com.audiobookshelf.android.podcast

import android.util.Log
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiClient
import io.socket.client.IO
import io.socket.client.Socket
import io.socket.engineio.client.transports.WebSocket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import org.json.JSONObject

/** The server's socket.io feed for the active account: progress, item and podcast download events. */
class ServerEvents(private val scope: CoroutineScope, private val accounts: AccountStore, private val http: OkHttpClient) {
    data class Event(val account: AccountIdentity, val name: String, val data: JSONObject?)

    private val stream = MutableSharedFlow<Event>(extraBufferCapacity = 64)
    val events: SharedFlow<Event> = stream
    private val authenticated = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = authenticated
    private var socket: Socket? = null

    fun start() {
        scope.launch {
            accounts.session.map { (it as? SessionState.Active)?.client }.distinctUntilChanged { a, b -> a === b }.collect { client ->
                disconnect()
                if (client != null) connect(client)
            }
        }
    }

    private fun connect(client: ApiClient) {
        val base = client.address.base
        val origin = base.newBuilder().encodedPath("/").build().toString().trimEnd('/')
        val options = IO.Options.builder()
            .setPath(base.encodedPath.trimEnd('/') + "/socket.io")
            .setTransports(arrayOf(WebSocket.NAME))
            .setReconnection(true)
            .build()
        options.callFactory = http
        options.webSocketFactory = http
        val account = client.account
        val connection = IO.socket(origin, options)
        var sent: String? = null
        var retried = false
        connection.on(Socket.EVENT_CONNECT) {
            retried = false
            scope.launch {
                runCatching { client.bearer() }.onSuccess { sent = it; connection.emit("auth", it) }.onFailure { accounts.handle(it) }
            }
        }
        connection.on("init") { authenticated.value = true; stream.tryEmit(Event(account, "init", null)) }
        connection.on("auth_failed") {
            authenticated.value = false
            val rejected = sent
            if (retried || rejected == null) { Log.i(TAG, "Realtime authentication rejected"); return@on }
            retried = true
            scope.launch {
                runCatching { client.bearerAfterRejection(rejected) }.onSuccess { sent = it; connection.emit("auth", it) }.onFailure { accounts.handle(it) }
            }
        }
        connection.on(Socket.EVENT_DISCONNECT) { authenticated.value = false }
        for (name in FORWARDED) connection.on(name) { args -> stream.tryEmit(Event(account, name, args.firstOrNull() as? JSONObject)) }
        socket = connection
        connection.connect()
    }

    private fun disconnect() {
        socket?.off()
        socket?.disconnect()
        socket = null
        authenticated.value = false
    }

    private companion object {
        const val TAG = "AbsRealtime"
        val FORWARDED = listOf("episode_download_finished", "episode_added", "item_updated", "item_added", "user_item_progress_updated")
    }
}
