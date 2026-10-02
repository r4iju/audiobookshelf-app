package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SearchModel
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.LibraryItem

@Composable
fun SearchScreen(search: SearchModel, catalog: CatalogModel, padding: PaddingValues, open: (LibraryItem) -> Unit, openFiltered: (filter: String, label: String) -> Unit) {
    val focus = remember { FocusRequester() }
    val client = LocalContext.current.graph.accounts.activeClient
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val booksHeading = stringResource(R.string.search_books)
    val podcastsHeading = stringResource(R.string.search_podcasts)
    val episodesHeading = stringResource(R.string.search_episodes)
    val authorsHeading = stringResource(R.string.search_authors)
    val seriesHeading = stringResource(R.string.search_series)
    val narratorsHeading = stringResource(R.string.search_narrators)
    val tagsHeading = stringResource(R.string.search_tags)
    LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("search-results"), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            OutlinedTextField(
                value = search.query, onValueChange = { search.update(it, catalog.library?.id) },
                placeholder = { Text("Search ${catalog.library?.name ?: "library"}") },
                leadingIcon = { Icon(Icons.Outlined.Search, null) },
                trailingIcon = { if (search.query.isNotEmpty()) IconButton(onClick = { search.update("", catalog.library?.id) }) { Icon(Icons.Outlined.Close, "Clear search") } },
                singleLine = true, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier.fillMaxWidth().padding(16.dp).focusRequester(focus).testTag("search-field"),
            )
            if (search.loading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = 16.dp))
        }
        val results = search.results
        val error = search.error
        when {
            error != null -> item { MessageState("Search failed", error, tag = "search-error", action = "Retry", actionTag = "search-retry") { search.retry() } }
            search.query.isBlank() -> item { MessageState("Find something to listen to", "Search titles, authors, series, narrators and episodes.", icon = Icons.Outlined.Search, tag = "search-idle") }
            results == null -> Unit
            results.isEmpty -> item { MessageState(stringResource(R.string.search_no_results), "Nothing matches \"${search.query}\". Try fewer words or another spelling.", icon = Icons.Outlined.Search, tag = "search-empty") }
            else -> {
                section(booksHeading, results.book.map { it.libraryItem }) { ResultRow(it, client, "search-item-${it.id}") { open(it) } }
                section(podcastsHeading, results.podcast.map { it.libraryItem }) { ResultRow(it, client, "search-item-${it.id}") { open(it) } }
                section(episodesHeading, results.episodes.map { it.libraryItem }) { ResultRow(it, client, "search-episode-${it.recentEpisode?.id ?: it.id}") { open(it) } }
                section(authorsHeading, results.authors) { author ->
                    LinkRow(author.name, author.numBooks?.let { "$it books" }, Icons.Outlined.Person, "search-author-${author.id}") { openFiltered(ApiClient.filter("authors", author.id), author.name) }
                }
                section(seriesHeading, results.series) { series ->
                    LinkRow(series.series.name, "${series.books.size} books", Icons.AutoMirrored.Outlined.LibraryBooks, "search-series-${series.series.id}") { openFiltered(ApiClient.filter("series", series.series.id), series.series.name) }
                }
                section(narratorsHeading, results.narrators) { narrator ->
                    LinkRow(narrator.name, "${narrator.numBooks} books", Icons.Outlined.RecordVoiceOver, "search-narrator-${narrator.name}") { openFiltered(ApiClient.filter("narrators", narrator.name), narrator.name) }
                }
                section(tagsHeading, results.tags) { tag ->
                    LinkRow(tag.name, "${tag.numItems} items", Icons.Outlined.Sell, "search-tag-${tag.name}") { openFiltered(ApiClient.filter("tags", tag.name), tag.name) }
                }
            }
        }
    }
}

private fun <T> androidx.compose.foundation.lazy.LazyListScope.section(title: String, entries: List<T>, row: @Composable (T) -> Unit) {
    if (entries.isEmpty()) return
    item { SectionTitle(title) }
    items(entries) { row(it) }
}

@Composable
private fun ResultRow(item: LibraryItem, client: ApiClient?, tag: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(item.recentEpisode?.title ?: item.title, maxLines = 2) },
        supportingContent = { Text(if (item.recentEpisode != null) item.title else item.author, maxLines = 1) },
        leadingContent = { Box(Modifier.widthIn(max = 56.dp)) { Cover(client?.coverUrl(item.id)?.toString(), item.title, Modifier.fillMaxWidth(), podcast = item.isPodcast) } },
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick).testTag(tag),
    )
}

@Composable
private fun LinkRow(title: String, detail: String?, icon: androidx.compose.ui.graphics.vector.ImageVector, tag: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = detail?.let { { Text(it) } },
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick).testTag(tag),
    )
}
