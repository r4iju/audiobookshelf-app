package com.audiobookshelf.android.ui

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
        add("genres" to "Genre"); add("tags" to "Tag")
        if (!podcast) { add("series" to "Series"); add("authors" to "Author"); add("narrators" to "Narrator"); add("languages" to "Language"); add("progress" to "Progress"); add("ebooks" to "Ebooks") }
    }
    fun options(key: String): List<FilterOption> = when (key) {
        "genres" -> data?.genres.orEmpty().map { FilterOption(it, it) }
        "tags" -> data?.tags.orEmpty().map { FilterOption(it, it) }
        "series" -> listOf(FilterOption("No series", "no-series")) + data?.series.orEmpty().map { FilterOption(it.name, it.id) }
        "authors" -> data?.authors.orEmpty().map { FilterOption(it.name, it.id) }
        "narrators" -> data?.narrators.orEmpty().map { FilterOption(it, it) }
        "languages" -> data?.languages.orEmpty().map { FilterOption(it, it) }
        "progress" -> listOf(FilterOption("Finished", "finished"), FilterOption("In progress", "in-progress"), FilterOption("Not started", "not-started"), FilterOption("Not finished", "not-finished"))
        "ebooks" -> listOf(FilterOption("Has ebook", "ebook"), FilterOption("Has supplementary ebook", "supplementary"))
        else -> emptyList()
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        val selected = group
        LazyColumn(Modifier.fillMaxWidth().testTag("filter-sheet"), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (selected == null) {
                item { SectionTitle("Filter") }
                item {
                    ListItem(headlineContent = { Text("All") }, trailingContent = { if (catalog.query.filter == null) Icon(Icons.Outlined.Check, "Selected") },
                        modifier = Modifier.clickable(role = Role.Button) { catalog.apply(catalog.query.copy(filter = null, filterLabel = null)); onDismiss() }.testTag("filter-all"))
                }
                items(groups) { (key, label) ->
                    ListItem(headlineContent = { Text(label) }, trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) },
                        modifier = Modifier.clickable(role = Role.Button) { group = key }.testTag("filter-group-$key"))
                }
            } else {
                item {
                    ListItem(headlineContent = { Text(groups.first { it.first == selected }.second, style = MaterialTheme.typography.titleLarge) },
                        leadingContent = { IconButton(onClick = { group = null }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "All filters") } })
                }
                val entries = options(selected)
                if (entries.isEmpty()) item { Text(if (data == null) "Loading…" else "Nothing to filter by here.", Modifier.padding(24.dp)) }
                items(entries) { option ->
                    val value = ApiClient.filter(selected, option.value)
                    ListItem(headlineContent = { Text(option.label) }, trailingContent = { if (catalog.query.filter == value) Icon(Icons.Outlined.Check, "Selected") },
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
        "media.metadata.title" to "Title", "media.metadata.author" to "Author", "addedAt" to "Date added", "size" to "Size",
        "media.numTracks" to "Number of episodes", "birthtimeMs" to "File created", "mtimeMs" to "File modified", "random" to "Random",
    ) else listOf(
        "media.metadata.title" to "Title", "media.metadata.authorName" to "Author (first last)", "media.metadata.authorNameLF" to "Author (last, first)",
        "media.metadata.publishedYear" to "Published year", "addedAt" to "Date added", "size" to "Size", "media.duration" to "Duration",
        "birthtimeMs" to "File created", "mtimeMs" to "File modified", "progress" to "Progress: last updated",
        "progress.createdAt" to "Progress: started", "progress.finishedAt" to "Progress: finished", "random" to "Random",
    )
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.testTag("sort-sheet")) {
            ListItem(
                headlineContent = { Text("Sort", style = MaterialTheme.typography.titleLarge) },
                trailingContent = {
                    IconButton(onClick = { onChange(catalog.query.sort, !catalog.query.descending) }, modifier = Modifier.testTag("sort-direction")) {
                        Icon(Icons.Outlined.SwapVert, if (catalog.query.descending) "Descending, switch to ascending" else "Ascending, switch to descending")
                    }
                },
            )
            LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                items(options) { (value, label) ->
                    ListItem(
                        headlineContent = { Text(label) },
                        trailingContent = { if (catalog.query.sort == value) Text(if (catalog.query.descending) "Descending" else "Ascending", color = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.clickable(role = Role.Button) {
                            onChange(value, if (catalog.query.sort == value) !catalog.query.descending else value == "addedAt" || value.startsWith("progress"))
                        }.testTag("sort-$value"),
                    )
                }
            }
        }
    }
}
