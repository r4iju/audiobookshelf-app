package com.audiobookshelf.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.LibraryBooks
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.DownloadForOffline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.viewmodel.compose.viewModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.LibraryItem

@Composable
fun AppRoot() {
    val graph = LocalContext.current.graph
    val settings by graph.settings.settings.collectAsState()
    val session by graph.accounts.session.collectAsState()
    AbsTheme(settings.appearance) {
        when (val state = session) {
            SessionState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            is SessionState.SignedOut -> ConnectScreen(state)
            is SessionState.Active -> SignedIn(state)
        }
    }
}

@Composable
private fun SignedIn(active: SessionState.Active) {
    val model: MainViewModel = viewModel()
    val graph = LocalContext.current.graph
    val catalog = model.catalogFor(active)
    val route = model.stack.lastOrNull()
    val pop: () -> Unit = { model.pop() }
    BackHandler(enabled = route != null) { model.pop() }
    BackHandler(enabled = route == null && model.tab.value != Tab.Library) { model.tab.value = Tab.Library }

    val open: (LibraryItem) -> Unit = { item ->
        val episode = item.recentEpisode
        model.push(if (episode != null) Route.Episode(item.id, episode.id) else Route.Item(item.id))
    }
    val openFiltered: (String, String) -> Unit = { filter, label -> model.push(Route.Filtered(filter, label)) }
    val itemActions = ItemActions(
        onAuthor = { id, name -> openFiltered(ApiClient.filter("authors", id), name) },
        onSeries = { id, name -> openFiltered(ApiClient.filter("series", id), name) },
        onNarrator = { name -> openFiltered(ApiClient.filter("narrators", name), name) },
        onGenre = { name -> openFiltered(ApiClient.filter("genres", name), name) },
    )

    LaunchedEffect(catalog.user) {
        catalog.user?.let { user ->
            graph.downloads.adoptRemote(active.client.account, user.mediaProgress)
            user.mediaProgress.filter { it.ebookLocation != null && it.episodeId == null }.forEach { progress ->
                runCatching { graph.reading.adoptRemote(active.client.account, progress.libraryItemId, PRIMARY_EBOOK, progress) }
            }
        }
    }
    LaunchedEffect(Unit) {
        graph.openPlayerRequests.collect { if (graph.playback.state.value.now != null && model.stack.lastOrNull() != Route.Player) model.push(Route.Player) }
    }
    val mini: @Composable () -> Unit = { MiniPlayer(onOpen = { model.push(Route.Player) }) }

    CompositionLocalProvider(LocalBottomAccessory provides mini) {
        Box(Modifier.fillMaxSize()) {
            when (route) {
                null -> Home(model, active, open, openFiltered)
                Route.Player -> PlayerScreen(onCollapse = pop, onClosed = pop)
                Route.Accounts -> RouteScaffold("Accounts", pop) { AccountsScreen(active, it) }
                is Route.Item -> RouteScaffold("", pop) { padding ->
                    LoadItem(active.client, route.id, padding, graph.accounts::handle) { item, reload ->
                        if (item.isPodcast) {
                            PodcastDetail(item, reload, active, catalog, padding, itemActions, onEpisode = { model.push(Route.Episode(item.id, it)) }, onPlayer = { model.push(Route.Player) })
                            return@LoadItem
                        }
                        val cover = active.client.coverUrl(item.id).toString()
                        val progress = catalog.progressFor(item.id)
                        ItemDetail(item, cover, progress, padding, itemActions, primary = {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (item.media.tracks.isNotEmpty()) PlayButton({ preferDownloaded(graph, active, item.id, null, progress) ?: PlaySource.Stream(active.client, item.id, null, cover, progress?.lastUpdate) },
                                    item.id, null, onOpened = { model.push(Route.Player) })
                                ReadButtons(item, onRead = model::push)
                            }
                        }, extra = {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                DownloadButton(item, null, active, catalog)
                                AddToGroupButton(item.id, null, active, catalog)
                            }
                        })
                    }
                }
                is Route.Episode -> RouteScaffold("", pop) { padding ->
                    LoadItem(active.client, route.itemId, padding, graph.accounts::handle) { item, _ ->
                        EpisodeScreen(item, route.episodeId, active, catalog, padding, onPlayer = { model.push(Route.Player) })
                    }
                }
                is Route.Groups -> RouteScaffold(if (route.kind == COLLECTIONS) "Collections" else "Playlists", pop, actions = {
                    if (canCreateGroup(route.kind, catalog)) IconButton(onClick = { model.push(Route.GroupEditor(route.kind, null)) }, modifier = Modifier.testTag("new-group")) {
                        Icon(Icons.Outlined.Add, if (route.kind == COLLECTIONS) "New collection" else "New playlist")
                    }
                }) { padding -> GroupsScreen(route.kind, active, catalog, padding, onOpen = { model.push(Route.Group(route.kind, it)) }) }
                is Route.Group -> RouteScaffold("", pop) { padding ->
                    GroupScreen(route.kind, route.id, active, catalog, padding,
                        onMember = { member -> model.push(if (member.episodeId != null) Route.Episode(member.itemId, member.episodeId) else Route.Item(member.itemId)) },
                        onEdit = { model.push(Route.GroupEditor(route.kind, route.id)) },
                        onDeleted = pop)
                }
                is Route.GroupEditor -> RouteScaffold(if (route.id == null) (if (route.kind == COLLECTIONS) "New collection" else "New playlist") else "Edit", pop) { padding ->
                    GroupEditorScreen(route.kind, route.id, active, catalog, padding, onSaved = { id ->
                        model.pop()
                        if (route.id == null) model.push(Route.Group(route.kind, id))
                    })
                }
                is Route.Reader -> PdfReaderScreen(route, active, catalog, onClose = pop)
                Route.AddPodcast -> RouteScaffold("Add podcast", pop) { padding -> AddPodcastScreen(active, catalog, padding, onCreated = pop) }
                is Route.Filtered -> RouteScaffold(route.label, pop) { padding ->
                    val libraryId = catalog.library?.id
                    if (libraryId != null) FilteredScreen(model.filtered(active, libraryId, route), padding, { catalog.progressFor(it) }, open)
                }
                else -> RouteScaffold("", pop) { padding ->
                    Box(Modifier.padding(padding)) { MessageState("Not available yet", "This part of the preview is still being built.", tag = "unavailable") }
                }
            }
        }
    }
}

@Composable
private fun Home(model: MainViewModel, active: SessionState.Active, open: (LibraryItem) -> Unit, openFiltered: (String, String) -> Unit) {
    val graph = LocalContext.current.graph
    val catalog = model.catalogFor(active)
    var sheet by remember { mutableStateOf<String?>(null) }
    val tab = model.tab.value
    Scaffold(
        topBar = {
            if (tab == Tab.Library) LibraryTopBar(catalog) {
                if (catalog.library?.isPodcast == true && catalog.user?.isAdmin == true) {
                    IconButton(onClick = { model.push(Route.AddPodcast) }, modifier = Modifier.testTag("add-podcast")) { Icon(Icons.Outlined.Add, "Add podcast") }
                }
                LibraryMenu(catalog, onRoute = model::push)
                IconButton(onClick = { model.push(Route.Accounts) }, modifier = Modifier.testTag("open-accounts")) { Icon(Icons.Outlined.AccountCircle, "Accounts") }
                IconButton(onClick = { model.push(Route.Settings) }, modifier = Modifier.testTag("open-settings")) { Icon(Icons.Outlined.Settings, "Settings") }
            }
        },
        bottomBar = {
            Column {
            LocalBottomAccessory.current()
            NavigationBar {
                NavigationBarItem(selected = tab == Tab.Library, onClick = { model.tab.value = Tab.Library }, icon = { Icon(Icons.Outlined.LibraryBooks, null) }, label = { Text("Library") }, modifier = Modifier.testTag("tab-library"))
                NavigationBarItem(selected = tab == Tab.Search, onClick = { model.tab.value = Tab.Search }, icon = { Icon(Icons.Outlined.Search, null) }, label = { Text("Search") }, modifier = Modifier.testTag("tab-search"))
                NavigationBarItem(selected = tab == Tab.Downloads, onClick = { model.tab.value = Tab.Downloads }, icon = { Icon(Icons.Outlined.DownloadForOffline, null) }, label = { Text("Downloads") }, modifier = Modifier.testTag("tab-downloads"))
            }
            }
        },
    ) { padding ->
        when (tab) {
            Tab.Library -> LibraryScreen(catalog, padding, open, onFilter = { sheet = "filter" }, onSort = { sheet = "sort" })
            Tab.Search -> SearchScreen(model.search(active), catalog, padding, open, openFiltered)
            Tab.Downloads -> DownloadsScreen(active, catalog, padding, onRead = model::push)
        }
    }
    when (sheet) {
        "filter" -> FilterSheet(catalog) { sheet = null }
        "sort" -> SortSheet(catalog, onChange = { sort, descending ->
            graph.settings.update { it.copy(catalogSort = sort, catalogDescending = descending) }
            catalog.apply(catalog.query.copy(sort = sort, descending = descending))
        }) { sheet = null }
    }
}

@Composable
private fun LibraryMenu(catalog: com.audiobookshelf.android.data.CatalogModel, onRoute: (Route) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.testTag("library-menu")) { Icon(Icons.Outlined.MoreVert, "More") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (catalog.library?.isPodcast == false) DropdownMenuItem(text = { Text("Collections") }, onClick = { open = false; onRoute(Route.Groups(COLLECTIONS)) }, modifier = Modifier.testTag("menu-collections"))
            DropdownMenuItem(text = { Text("Playlists") }, onClick = { open = false; onRoute(Route.Groups(PLAYLISTS)) }, modifier = Modifier.testTag("menu-playlists"))
        }
    }
}

/** A finished download plays from this device even when the server is reachable, like the existing app. */
fun preferDownloaded(graph: com.audiobookshelf.android.AppGraph, active: SessionState.Active, itemId: String, episodeId: String?, progress: com.audiobookshelf.core.MediaProgress?): PlaySource? =
    graph.downloads.find(active.client.account, itemId, episodeId)
        ?.takeIf { it.state == com.audiobookshelf.android.download.DownloadStore.State.COMPLETE }
        ?.let { graph.downloads.localSource(it, progress) }
