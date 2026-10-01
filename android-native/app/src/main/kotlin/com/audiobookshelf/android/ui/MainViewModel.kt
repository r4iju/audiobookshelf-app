package com.audiobookshelf.android.ui

import android.app.Application
import androidx.compose.runtime.mutableStateListOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.CatalogQuery
import com.audiobookshelf.android.data.PagedItems
import com.audiobookshelf.android.data.SearchModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph

sealed interface Route {
    data class Item(val id: String) : Route
    data class Episode(val itemId: String, val episodeId: String) : Route
    data object Player : Route
    data object Settings : Route
    data object Statistics : Route
    data object Downloads : Route
    data object Accounts : Route
    data object Diagnostics : Route
    data object LocalFolders : Route
    data class Groups(val kind: String) : Route
    data class Group(val kind: String, val id: String) : Route
    data class GroupEditor(val kind: String, val id: String?) : Route
    data class Author(val id: String, val name: String) : Route
    data class Series(val id: String, val name: String) : Route
    data class Filtered(val filter: String, val label: String) : Route
    data object AddPodcast : Route
    data class Reader(val itemId: String, val ino: String, val supplementary: Boolean, val title: String) : Route
    data class LocalItem(val id: String) : Route
}

enum class Tab { Library, Search, Downloads }

/** Activity-scoped UI state that must survive configuration changes. */
class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val graph = application.graph
    val stack = mutableStateListOf<Route>()
    val tab = androidx.compose.runtime.mutableStateOf(Tab.Library)
    private var catalog: CatalogModel? = null
    private var searchModel: SearchModel? = null
    private val retained = mutableMapOf<Route, Any>()

    init {
        viewModelScope.launch {
            graph.progressSync.published.collect { account -> catalog?.takeIf { it.client.account == account }?.refreshUser() }
        }
        viewModelScope.launch {
            graph.serverEvents.events.collect { event ->
                if (event.name == "user_item_progress_updated") catalog?.takeIf { it.client.account == event.account }?.refreshUser()
            }
        }
    }

    fun push(route: Route) { stack.add(route) }
    fun pop(): Boolean {
        val removed = stack.removeLastOrNull() ?: return false
        if (removed !in stack) retained.remove(removed)
        return true
    }
    fun resetNavigation() { stack.clear(); retained.clear(); tab.value = Tab.Library }

    /** Per-route state that survives configuration changes and is dropped when the route is popped. */
    @Suppress("UNCHECKED_CAST")
    fun <T : Any> retain(route: Route, create: () -> T): T = retained.getOrPut(route, create) as T

    fun search(active: SessionState.Active): SearchModel {
        val existing = searchModel
        if (existing != null && existing.client === active.client) return existing
        return SearchModel(viewModelScope, active.client, graph.accounts).also { searchModel = it }
    }

    fun filtered(active: SessionState.Active, libraryId: String, route: Route.Filtered): PagedItems =
        retain(route) { PagedItems(viewModelScope, active.client, graph.accounts, libraryId, route.filter, graph.settings.current.catalogSort) }

    fun catalogFor(active: SessionState.Active): CatalogModel {
        val existing = catalog
        if (existing != null && existing.client === active.client) return existing
        stack.clear(); retained.clear(); tab.value = Tab.Library
        val settings = graph.settings.current
        return CatalogModel(viewModelScope, active.client, graph.accounts, active.connection.libraryId, CatalogQuery(settings.catalogSort, settings.catalogDescending))
            .also { catalog = it; it.reload() }
    }
}
