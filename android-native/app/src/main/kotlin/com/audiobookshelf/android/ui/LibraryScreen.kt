package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material3.InputChip
import androidx.compose.material.icons.automirrored.outlined.ViewList
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress

/** Server shelves carry the legacy app's translation key; their ids are the fallback for older servers. */
@Composable
private fun shelfLabel(shelf: com.audiobookshelf.core.PersonalizedShelf): String {
    val resource = when (shelf.labelStringKey ?: shelf.id) {
        "LabelContinueListening", "continue-listening" -> R.string.shelf_continue_listening
        "LabelContinueReading", "continue-reading" -> R.string.shelf_continue_reading
        "LabelContinueSeries", "continue-series" -> R.string.shelf_continue_series
        "LabelRecentlyAdded", "recently-added" -> R.string.shelf_recently_added
        "LabelRecentSeries", "recent-series" -> R.string.shelf_recent_series
        "LabelListenAgain", "listen-again" -> R.string.shelf_listen_again
        "LabelDiscover", "discover" -> R.string.shelf_discover
        "LabelNewestEpisodes", "newest-episodes" -> R.string.shelf_newest_episodes
        "LabelNewestAuthors", "newest-authors" -> R.string.shelf_newest_authors
        else -> return shelf.label
    }
    return stringResource(resource)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryTopBar(catalog: CatalogModel, actions: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    TopAppBar(
        title = {
            Box {
                TextButton(onClick = { open = true }, modifier = Modifier.testTag("library-picker")) {
                    Text(catalog.library?.name ?: stringResource(R.string.tab_library), style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Icon(Icons.Outlined.ArrowDropDown, stringResource(R.string.choose_library))
                }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    catalog.libraries.forEach { library ->
                        DropdownMenuItem(
                            text = { Text(library.name) },
                            onClick = { open = false; catalog.select(library) },
                            modifier = Modifier.testTag("library-option-${library.id}"),
                        )
                    }
                }
            }
        },
        actions = { actions() },
    )
}

@Composable
fun LibraryScreen(catalog: CatalogModel, padding: PaddingValues, open: (LibraryItem) -> Unit, onFilter: () -> Unit, onSort: () -> Unit) {
    val graph = LocalContext.current.graph
    val settings by graph.settings.settings.collectAsState()
    val list = settings.listLayout
    val state = rememberLazyGridState()
    LoadMoreWhenNearEnd(state, catalog)
    Box(Modifier.fillMaxSize().padding(padding).testTag("library-home")) {
        LazyVerticalGrid(
            columns = if (list) GridCells.Fixed(1) else GridCells.Adaptive(140.dp),
            state = state,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(if (list) 4.dp else 18.dp),
            modifier = Modifier.fillMaxSize().testTag("catalog-grid"),
        ) {
            val error = catalog.error
            when {
                error != null -> item(span = { GridItemSpan(maxLineSpan) }) {
                    MessageState(stringResource(R.string.lib_unavailable), stringResource(R.string.lib_unavailable_message, error), tag = "catalog-error", action = stringResource(R.string.action_retry), actionTag = "catalog-retry") { catalog.reload() }
                }
                catalog.loading -> item(span = { GridItemSpan(maxLineSpan) }) {
                    Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                }
                else -> {
                    catalog.shelves.forEach { shelf ->
                        item(span = { GridItemSpan(maxLineSpan) }, key = "shelf-${shelf.id}") {
                            Column(Modifier.padding(top = 8.dp)) {
                                Text(shelfLabel(shelf), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(vertical = 8.dp))
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.testTag("shelf-${shelf.id}")) {
                                    items(shelf.items(), key = { it.id + (it.recentEpisode?.id ?: "") }) { item ->
                                        ItemCard(item, catalog.progressFor(item.id, item.recentEpisode?.id), Modifier.width(if (shelf.id == "continue-listening") 168.dp else 132.dp), tagPrefix = "shelf-item") { open(item) }
                                    }
                                }
                            }
                        }
                    }
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                stringResource(R.string.lib_heading_with_total, catalog.query.filterLabel ?: if (catalog.library?.isPodcast == true) stringResource(R.string.all_podcasts) else stringResource(R.string.all_titles), catalog.total),
                                style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f),
                            )
                            IconButton(onClick = onFilter, modifier = Modifier.testTag("open-filter")) { Icon(Icons.Outlined.FilterList, stringResource(R.string.filter)) }
                            IconButton(onClick = onSort, modifier = Modifier.testTag("open-sort")) { Icon(Icons.AutoMirrored.Outlined.Sort, stringResource(R.string.sort)) }
                            IconButton(onClick = { graph.settings.update { it.copy(listLayout = !it.listLayout) } }, modifier = Modifier.testTag("toggle-layout")) {
                                Icon(if (list) Icons.Outlined.GridView else Icons.AutoMirrored.Outlined.ViewList, if (list) stringResource(R.string.lib_show_covers) else stringResource(R.string.lib_show_list))
                            }
                        }
                    }
                    if (catalog.query.filter != null) item(span = { GridItemSpan(maxLineSpan) }) {
                        Row { InputChip(selected = true, onClick = { catalog.apply(catalog.query.copy(filter = null, filterLabel = null)) },
                            label = { Text(catalog.query.filterLabel ?: stringResource(R.string.lib_filtered)) }, trailingIcon = { Icon(Icons.Outlined.Close, stringResource(R.string.action_clear_filter)) },
                            modifier = Modifier.testTag("clear-filter")) }
                    }
                    if (catalog.items.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                        MessageState(stringResource(R.string.lib_empty_title), stringResource(R.string.lib_empty_message), tag = "catalog-empty")
                    }
                    itemsIndexed(catalog.items, key = { _, item -> item.id }) { _, item ->
                        if (list) ItemRow(item, catalog.progressFor(item.id)) { open(item) }
                        else ItemCard(item, catalog.progressFor(item.id), Modifier.fillMaxWidth()) { open(item) }
                    }
                    if (catalog.pageLoading) item(span = { GridItemSpan(maxLineSpan) }) {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(28.dp)) }
                    }
                    catalog.pageError?.let { failure ->
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            MessageState(stringResource(R.string.lib_page_error), failure, tag = "page-error", action = stringResource(R.string.action_retry), actionTag = "page-retry") { catalog.retryPage() }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadMoreWhenNearEnd(state: LazyGridState, catalog: CatalogModel) {
    LaunchedEffect(state, catalog) {
        snapshotFlow { state.layoutInfo.visibleItemsInfo.lastOrNull()?.index to state.layoutInfo.totalItemsCount }
            .collect { (last, count) -> if (last != null && count > 0 && last >= count - 4) catalog.loadMore() }
    }
}

@Composable
fun ItemCard(item: LibraryItem, progress: MediaProgress?, modifier: Modifier = Modifier, tagPrefix: String = "item", onClick: () -> Unit) {
    val named = (item.recentEpisode?.title ?: item.title).let { if (item.author.isNotEmpty()) "$it, ${item.author}" else it }
    val description = when {
        progress == null -> named
        progress.isFinished -> stringResource(R.string.lib_card_finished, named)
        progress.progress > 0 -> stringResource(R.string.lib_card_percent_listened, named, (progress.progress * 100).toInt())
        else -> named
    }
    Column(
        modifier
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .testTag("$tagPrefix-${item.id}"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val context = LocalContext.current
        Cover(context.graph.accounts.activeClient?.coverUrl(item.id)?.toString(), item.title, Modifier.fillMaxWidth(), podcast = item.isPodcast)
        if (progress != null && (progress.progress > 0 || progress.isFinished)) ProgressLine(if (progress.isFinished) 1.0 else progress.progress)
        Text(item.recentEpisode?.title ?: item.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (item.author.isNotEmpty()) Text(item.author, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun ItemRow(item: LibraryItem, progress: MediaProgress?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(vertical = 6.dp).testTag("item-${item.id}"),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        val context = LocalContext.current
        Cover(context.graph.accounts.activeClient?.coverUrl(item.id)?.toString(), item.title, Modifier.size(64.dp), podcast = item.isPodcast)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(item.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (item.author.isNotEmpty()) Text(item.author, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val duration = item.duration
            if (!item.isPodcast && duration > 0) Text(formatDuration(duration), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (progress != null && progress.progress > 0) ProgressLine(if (progress.isFinished) 1.0 else progress.progress)
        }
    }
}
