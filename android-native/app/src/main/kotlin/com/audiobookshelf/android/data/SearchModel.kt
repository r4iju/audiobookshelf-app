package com.audiobookshelf.android.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ItemsPage
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.SearchResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Debounced library search; only the latest query's results are ever shown. */
class SearchModel(private val scope: CoroutineScope, val client: ApiClient, private val accounts: AccountStore) {
    var query by mutableStateOf(""); private set
    var results by mutableStateOf<SearchResponse?>(null); private set
    var loading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    private var job: Job? = null
    private var libraryId: String? = null

    fun update(text: String, library: String?) {
        query = text
        libraryId = library
        job?.cancel()
        if (text.isBlank() || library == null) { results = null; loading = false; error = null; return }
        loading = true; error = null
        job = scope.launch {
            delay(300)
            try {
                results = client.search(library, text.trim(), limit = 25)
            } catch (failure: Exception) {
                if (failure is kotlinx.coroutines.CancellationException) throw failure
                error = failure.localizedMessage; accounts.handle(failure)
            } finally { loading = false }
        }
    }

    fun retry() = update(query, libraryId)
}

/** A filtered, paginated item list (author, series, narrator, genre) inside one library. */
class PagedItems(private val scope: CoroutineScope, private val client: ApiClient, private val accounts: AccountStore, private val libraryId: String, private val filter: String, private val sort: String) {
    var items by mutableStateOf<List<LibraryItem>>(emptyList()); private set
    var total by mutableStateOf(0); private set
    var loading by mutableStateOf(true); private set
    var error by mutableStateOf<String?>(null); private set
    private var page = 0
    private var busy = false

    init { loadMore() }

    fun loadMore() {
        if (busy || (page > 0 && items.size >= total)) return
        busy = true; loading = true; error = null
        scope.launch {
            try {
                val next: ItemsPage = client.items(libraryId, page, sort = sort, filter = filter)
                val known = items.mapTo(HashSet()) { it.id }
                items = items + next.results.filter { it.id !in known }
                total = next.total; page += 1
            } catch (failure: Exception) {
                error = failure.localizedMessage; accounts.handle(failure)
            } finally { busy = false; loading = false }
        }
    }
}
