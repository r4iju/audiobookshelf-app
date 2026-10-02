package com.audiobookshelf.android.data

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.FilterData
import com.audiobookshelf.core.Library
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.PersonalizedShelf
import com.audiobookshelf.core.User
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

data class CatalogQuery(val sort: String = "media.metadata.title", val descending: Boolean = false, val filter: String? = null, val filterLabel: String? = null)

/**
 * Catalog for the active account. Each library switch or query change starts a new generation;
 * responses from an older generation are dropped so results never leak between libraries.
 */
class CatalogModel(private val scope: CoroutineScope, val client: ApiClient, private val accounts: AccountStore, savedLibraryId: String?, initialQuery: CatalogQuery, private val report: Report = { _, _, _ -> }) {
    var libraries by mutableStateOf<List<Library>>(emptyList()); private set
    var library by mutableStateOf<Library?>(null); private set
    var shelves by mutableStateOf<List<PersonalizedShelf>>(emptyList()); private set
    var items by mutableStateOf<List<LibraryItem>>(emptyList()); private set
    var total by mutableStateOf(0); private set
    var loading by mutableStateOf(true); private set
    var pageLoading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var pageError by mutableStateOf<String?>(null); private set
    var user by mutableStateOf<User?>(null); private set
    var query by mutableStateOf(initialQuery); private set
    var filterData by mutableStateOf<FilterData?>(null); private set

    private var generation = 0
    private var nextPage = 0
    private var pageJob: Job? = null
    private var preferredLibraryId = savedLibraryId

    val endReached get() = items.size >= total && !loading

    fun progressFor(itemId: String, episodeId: String? = null): MediaProgress? =
        user?.mediaProgress?.firstOrNull { it.libraryItemId == itemId && it.episodeId == episodeId }

    fun reload() {
        val current = ++generation
        loading = true; error = null; pageError = null
        pageJob?.cancel()
        scope.launch {
            try {
                val all = client.libraries()
                if (current != generation) return@launch
                libraries = all
                val selected = all.firstOrNull { it.id == (library?.id ?: preferredLibraryId) } ?: all.firstOrNull()
                library = selected
                if (selected == null) { items = emptyList(); total = 0; shelves = emptyList(); loading = false; return@launch }
                loadLibrary(selected, current)
            } catch (failure: Exception) {
                if (current == generation) fail(failure)
            }
        }
    }

    fun select(target: Library) {
        if (target.id == library?.id) return
        accounts.selectLibrary(target.id)
        preferredLibraryId = target.id
        library = target
        filterData = null
        query = CatalogQuery(query.sort, query.descending)
        val current = ++generation
        pageJob?.cancel()
        items = emptyList(); shelves = emptyList(); total = 0; loading = true; error = null; pageError = null
        scope.launch {
            try { loadLibrary(target, current) } catch (failure: Exception) { if (current == generation) fail(failure) }
        }
    }

    fun apply(next: CatalogQuery) {
        val target = library ?: return
        query = next
        val current = ++generation
        pageJob?.cancel()
        items = emptyList(); total = 0; loading = true; error = null; pageError = null
        scope.launch {
            try { loadLibrary(target, current) } catch (failure: Exception) { if (current == generation) fail(failure) }
        }
    }

    fun loadMore() {
        val target = library ?: return
        if (loading || pageLoading || endReached || pageError != null) return
        val current = generation
        pageLoading = true
        pageJob = scope.launch {
            try {
                val page = client.items(target.id, nextPage, query.sort, query.descending, query.filter)
                if (current != generation) return@launch
                val known = items.mapTo(HashSet()) { it.id }
                items = items + page.results.filter { it.id !in known }
                total = page.total
                nextPage += 1
            } catch (failure: Exception) {
                if (current == generation) { pageError = failure.localizedMessage; accounts.handle(failure) }
            } finally {
                if (current == generation) pageLoading = false
            }
        }
    }

    fun loadFilterData() {
        val target = library ?: return
        scope.launch { runCatching { client.filterData(target.id) }.onSuccess { if (library?.id == target.id) filterData = it }.onFailure { accounts.handle(it) } }
    }

    fun retryPage() { pageError = null; loadMore() }

    /** Shows a confirmed server progress change before the next full refresh. */
    fun applyProgress(progress: MediaProgress) {
        val current = user ?: return
        val others = current.mediaProgress.filterNot { it.libraryItemId == progress.libraryItemId && it.episodeId == progress.episodeId }
        user = current.copy(mediaProgress = others + progress)
    }

    fun forgetProgress(itemId: String, episodeId: String?) {
        val current = user ?: return
        user = current.copy(mediaProgress = current.mediaProgress.filterNot { it.libraryItemId == itemId && it.episodeId == episodeId })
    }

    /** Reads progress made on other clients before choosing what to play. */
    suspend fun freshUser(): User = client.me().also { user = it }

    fun refreshUser() {
        scope.launch { runCatching { client.me() }.onSuccess { user = it }.onFailure { accounts.handle(it) } }
    }

    private suspend fun loadLibrary(target: Library, current: Int) = coroutineScope {
        val me = async { client.me() }
        val home = async { if (query.filter == null) runCatching { client.personalized(target.id) }.getOrElse { if (it is ApiError.SignInRequired) throw it; emptyList() } else emptyList() }
        val first = client.items(target.id, 0, query.sort, query.descending, query.filter)
        val profile = me.await()
        val personal = home.await()
        if (current != generation) return@coroutineScope
        user = profile
        shelves = personal.filter { it.items().isNotEmpty() }
        items = first.results.distinctBy { it.id }
        total = first.total
        nextPage = 1
        loading = false
    }

    private fun fail(failure: Throwable) {
        Log.w("AbsCatalog", "Catalog load failed", failure)
        report(Diagnostics.Area.CONNECTION, "The library could not be loaded from ${client.account.server}", failure)
        loading = false
        error = failure.localizedMessage.orEmpty()
        accounts.handle(failure)
    }
}
