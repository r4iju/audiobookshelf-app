package com.audiobookshelf.android.data

import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.AuthApi
import com.audiobookshelf.core.Credentials
import com.audiobookshelf.core.DeviceInfo
import com.audiobookshelf.core.ServerAddress
import com.audiobookshelf.core.ServerStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.OkHttpClient
import java.util.UUID

sealed interface SessionState {
    data object Loading : SessionState
    /** No active account: connection screen. [reauth] pre-fills a rejected account; saved data is kept. */
    data class SignedOut(val connections: List<SavedConnection>, val reauth: SavedConnection? = null, val notice: String? = null) : SessionState
    data class Active(val connection: SavedConnection, val client: ApiClient, val connections: List<SavedConnection>) : SessionState
}

/**
 * Owns saved server/account connections. Switching or signing out never touches listening
 * journals or downloads: those stay keyed by [AccountIdentity] until that account returns.
 */
class AccountStore(private val vault: CredentialVault, private val http: OkHttpClient, private val device: DeviceInfo) {
    private val state = MutableStateFlow<SessionState>(SessionState.Loading)
    val session: StateFlow<SessionState> = state
    private val auth = AuthApi(http)
    private val clients = mutableMapOf<String, ApiClient>()

    val activeClient: ApiClient? get() = (state.value as? SessionState.Active)?.client

    fun restore() {
        val document = try {
            vault.load()
        } catch (error: CredentialVault.Unreadable) {
            state.value = SessionState.SignedOut(emptyList(), notice = error.message)
            return
        }
        publish(document)
    }

    suspend fun probe(raw: String): Pair<ServerAddress, ServerStatus> {
        val address = ServerAddress.parse(raw)
        return address to auth.status(address)
    }

    suspend fun signIn(address: ServerAddress, username: String, password: String) {
        adopt(auth.login(address, username.trim(), password))
    }

    fun adopt(credentials: Credentials) {
        val document = vault.update { saved ->
            val existing = saved.connections.firstOrNull { it.credentials.account == credentials.account }
            val connection = existing?.copy(credentials = credentials, needsSignIn = false)
                ?: SavedConnection(UUID.randomUUID().toString(), credentials)
            saved.copy(connections = saved.connections.filterNot { it.id == connection.id } + connection, activeId = connection.id)
        }
        clients.clear()
        publish(document)
    }

    fun switchTo(id: String) = publish(vault.update { it.copy(activeId = id) })

    fun addAccount() {
        val saved = runCatching { vault.load() }.getOrNull()
        state.value = SessionState.SignedOut(saved?.connections.orEmpty())
    }

    fun cancelAddAccount() = restore()

    fun remove(id: String) {
        clients.remove(id)
        publish(vault.update { saved ->
            val remaining = saved.connections.filterNot { it.id == id }
            saved.copy(connections = remaining, activeId = saved.activeId.takeUnless { it == id } ?: remaining.firstOrNull()?.id)
        })
    }

    fun selectLibrary(libraryId: String) {
        val active = state.value as? SessionState.Active ?: return
        publish(vault.update { saved ->
            saved.copy(connections = saved.connections.map { if (it.id == active.connection.id) it.copy(libraryId = libraryId) else it })
        })
    }

    /** Called whenever the server rejects the current session: route to reauthentication, keep everything. */
    fun requireSignIn(account: AccountIdentity) {
        val document = vault.update { saved ->
            saved.copy(connections = saved.connections.map { if (it.credentials.account == account) it.copy(needsSignIn = true) else it })
        }
        clients.clear()
        publish(document)
    }

    fun handle(error: Throwable) {
        if (error is ApiError.SignInRequired) activeClient?.let { requireSignIn(it.account) }
    }

    private fun publish(document: VaultDocument) {
        val active = document.connections.firstOrNull { it.id == document.activeId } ?: document.connections.firstOrNull()
        state.value = when {
            active == null -> SessionState.SignedOut(document.connections)
            active.needsSignIn -> SessionState.SignedOut(document.connections, reauth = active,
                notice = "Your session for ${active.credentials.username} ended. Sign in again; unsent listening and downloads are kept.")
            else -> SessionState.Active(active, clientFor(active), document.connections)
        }
    }

    private fun clientFor(connection: SavedConnection): ApiClient {
        val existing = clients[connection.id]
        if (existing != null && existing.account == connection.credentials.account) return existing
        return ApiClient(http, connection.credentials, { previous, next ->
            vault.update { saved ->
                saved.copy(connections = saved.connections.map {
                    if (it.id == connection.id && it.credentials.accessToken == previous.accessToken) it.copy(credentials = next) else it
                })
            }
        }, device).also { clients[connection.id] = it }
    }
}
