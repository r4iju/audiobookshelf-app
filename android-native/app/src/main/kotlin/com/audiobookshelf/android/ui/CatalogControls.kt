package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.core.ApiClient

private data class FilterOption(val label: String, val value: String)

/** Filter groups mirroring the existing app: genre, tag, series, author, narrator, language, progress, ebooks. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterSheet(catalog: CatalogModel, onDismiss: () -> Unit) {
    LaunchedEffect(catalog.library?.id) { if (catalog.filterData == null) catalog.loadFilterData() }
    var group by remember { mutableStateOf<String?>(null) }
    val data = catalog.filterData
    val podcast = catalog.library?.isPodcast == true
    val groups = buildList {
        add("genres" to stringResource(R.string.lib_filter_genre)); add("tags" to stringResource(R.string.lib_filter_tag))
        if (!podcast) {
            add("series" to stringResource(R.string.search_series)); add("authors" to stringResource(R.string.lib_author)); add("narrators" to stringResource(R.string.lib_filter_narrator))
            add("languages" to stringResource(R.string.lib_filter_language)); add("progress" to stringResource(R.string.lib_filter_progress)); add("ebooks" to stringResource(R.string.lib_filter_ebooks))
        }
    }
    val noSeries = FilterOption(stringResource(R.string.lib_filter_no_series), "no-series")
    val progressOptions = listOf(
        FilterOption(stringResource(R.string.finished), "finished"), FilterOption(stringResource(R.string.lib_filter_in_progress), "in-progress"),
        FilterOption(stringResource(R.string.lib_filter_not_started), "not-started"), FilterOption(stringResource(R.string.lib_filter_not_finished), "not-finished"),
    )
    val ebookOptions = listOf(FilterOption(stringResource(R.string.lib_filter_has_ebook), "ebook"), FilterOption(stringResource(R.string.lib_filter_has_supplementary_ebook), "supplementary"))
    fun options(key: String): List<FilterOption> = when (key) {
        "genres" -> data?.genres.orEmpty().map { FilterOption(it, it) }
        "tags" -> data?.tags.orEmpty().map { FilterOption(it, it) }
        "series" -> listOf(noSeries) + data?.series.orEmpty().map { FilterOption(it.name, it.id) }
        "authors" -> data?.authors.orEmpty().map { FilterOption(it.name, it.id) }
        "narrators" -> data?.narrators.orEmpty().map { FilterOption(it, it) }
        "languages" -> data?.languages.orEmpty().map { FilterOption(it, it) }
        "progress" -> progressOptions
        "ebooks" -> ebookOptions
        else -> emptyList()
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        val selected = group
        LazyColumn(Modifier.fillMaxWidth().testTag("filter-sheet"), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (selected == null) {
                item { SectionTitle(stringResource(R.string.filter)) }
                item {
                    ListItem(headlineContent = { Text(stringResource(R.string.lib_filter_all)) }, trailingContent = { if (catalog.query.filter == null) Icon(Icons.Outlined.Check, stringResource(R.string.lib_selected)) },
                        modifier = Modifier.clickable(role = Role.Button) { catalog.apply(catalog.query.copy(filter = null, filterLabel = null)); onDismiss() }.testTag("filter-all"))
                }
                items(groups) { (key, label) ->
                    ListItem(headlineContent = { Text(label) }, trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) },
                        modifier = Modifier.clickable(role = Role.Button) { group = key }.testTag("filter-group-$key"))
                }
            } else {
                item {
                    ListItem(headlineContent = { Text(groups.first { it.first == selected }.second, style = MaterialTheme.typography.titleLarge) },
                        leadingContent = { IconButton(onClick = { group = null }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.lib_all_filters)) } })
                }
                val entries = options(selected)
                if (entries.isEmpty()) item { Text(if (data == null) stringResource(R.string.lib_loading) else stringResource(R.string.lib_nothing_to_filter), Modifier.padding(24.dp)) }
                items(entries) { option ->
                    val value = ApiClient.filter(selected, option.value)
                    ListItem(headlineContent = { Text(option.label) }, trailingContent = { if (catalog.query.filter == value) Icon(Icons.Outlined.Check, stringResource(R.string.lib_selected)) },
                        modifier = Modifier.clickable(role = Role.Button) { catalog.apply(catalog.query.copy(filter = value, filterLabel = option.label)); onDismiss() }
                            .testTag("filter-$selected-${option.value}"))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SortSheet(catalog: CatalogModel, onChange: (sort: String, descending: Boolean) -> Unit, onDismiss: () -> Unit) {
    val podcast = catalog.library?.isPodcast == true
    val options = if (podcast) listOf(
        "media.metadata.title" to stringResource(R.string.lib_sort_title), "media.metadata.author" to stringResource(R.string.lib_author),
        "addedAt" to stringResource(R.string.lib_sort_date_added), "size" to stringResource(R.string.lib_sort_size),
        "media.numTracks" to stringResource(R.string.lib_sort_number_of_episodes), "birthtimeMs" to stringResource(R.string.lib_sort_file_created),
        "mtimeMs" to stringResource(R.string.lib_sort_file_modified), "random" to stringResource(R.string.lib_sort_random),
    ) else listOf(
        "media.metadata.title" to stringResource(R.string.lib_sort_title), "media.metadata.authorName" to stringResource(R.string.lib_sort_author_first_last),
        "media.metadata.authorNameLF" to stringResource(R.string.lib_sort_author_last_first), "media.metadata.publishedYear" to stringResource(R.string.lib_sort_published_year),
        "addedAt" to stringResource(R.string.lib_sort_date_added), "size" to stringResource(R.string.lib_sort_size), "media.duration" to stringResource(R.string.lib_sort_duration),
        "birthtimeMs" to stringResource(R.string.lib_sort_file_created), "mtimeMs" to stringResource(R.string.lib_sort_file_modified),
        "progress" to stringResource(R.string.lib_sort_progress_updated), "progress.createdAt" to stringResource(R.string.lib_sort_progress_started),
        "progress.finishedAt" to stringResource(R.string.lib_sort_progress_finished), "random" to stringResource(R.string.lib_sort_random),
    )
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.testTag("sort-sheet")) {
            ListItem(
                headlineContent = { Text(stringResource(R.string.sort), style = MaterialTheme.typography.titleLarge) },
                trailingContent = {
                    IconButton(onClick = { onChange(catalog.query.sort, !catalog.query.descending) }, modifier = Modifier.testTag("sort-direction")) {
                        Icon(Icons.Outlined.SwapVert, if (catalog.query.descending) stringResource(R.string.lib_sort_descending_switch) else stringResource(R.string.lib_sort_ascending_switch))
                    }
                },
            )
            LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                items(options) { (value, label) ->
                    ListItem(
                        headlineContent = { Text(label) },
                        trailingContent = { if (catalog.query.sort == value) Text(if (catalog.query.descending) stringResource(R.string.lib_sort_descending) else stringResource(R.string.lib_sort_ascending), color = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.clickable(role = Role.Button) {
                            onChange(value, if (catalog.query.sort == value) !catalog.query.descending else value == "addedAt" || value.startsWith("progress"))
                        }.testTag("sort-$value"),
                    )
                }
            }
        }
    }
}
