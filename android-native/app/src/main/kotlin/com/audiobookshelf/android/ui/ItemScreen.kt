package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.text.HtmlCompat
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress

/** Loads one item with a retryable error state; the item is passed to [content] once available. */
@Composable
fun LoadItem(client: ApiClient, id: String, padding: PaddingValues, onFailure: (Throwable) -> Unit, content: @Composable (LibraryItem, () -> Unit) -> Unit) {
    var attempt by remember { mutableIntStateOf(0) }
    var item by remember(id) { mutableStateOf<LibraryItem?>(null) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    LaunchedEffect(id, attempt) {
        error = null
        try { item = client.item(id) } catch (failure: Exception) { error = failure.message; onFailure(failure) }
    }
    val loaded = item
    when {
        loaded != null -> content(loaded) { attempt++ }
        error != null -> Box(Modifier.padding(padding)) {
            MessageState("This title could not load", error, tag = "item-error", action = stringResource(R.string.action_retry), actionTag = "item-retry") { attempt++ }
        }
        else -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
    }
}

class ItemActions(
    val onAuthor: (id: String, name: String) -> Unit,
    val onSeries: (id: String, name: String) -> Unit,
    val onNarrator: (name: String) -> Unit,
    val onGenre: (name: String) -> Unit,
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ItemDetail(
    item: LibraryItem,
    coverUrl: String,
    progress: MediaProgress?,
    padding: PaddingValues,
    actions: ItemActions,
    primary: @Composable () -> Unit,
    extra: @Composable () -> Unit = {},
    more: LazyListScope.() -> Unit = {},
) {
    val metadata = item.media.metadata
    val description = remember(metadata.description) {
        metadata.description?.let { HtmlCompat.fromHtml(it, HtmlCompat.FROM_HTML_MODE_COMPACT).toString().trim() }?.takeIf { it.isNotEmpty() }
    }
    BoxWithConstraints(Modifier.fillMaxSize().padding(padding)) {
        val wide = maxWidth >= 640.dp
        LazyColumn(
            Modifier.fillMaxSize().testTag("item-detail"),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                val header: @Composable () -> Unit = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(item.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                        metadata.subtitle?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            val authors = metadata.authors.ifEmpty { item.author.takeIf { it.isNotEmpty() }?.let { listOf(com.audiobookshelf.core.NamedRef("", it)) } ?: emptyList() }
                            authors.forEach { author ->
                                TextButton(onClick = { if (author.id.isNotEmpty()) actions.onAuthor(author.id, author.name) }, enabled = author.id.isNotEmpty(), contentPadding = PaddingValues(vertical = 8.dp), modifier = Modifier.testTag("author-${author.id}")) {
                                    Text(author.name, style = MaterialTheme.typography.titleMedium)
                                }
                            }
                        }
                        if (item.narrators.isNotEmpty()) {
                            FlowRow(verticalArrangement = Arrangement.Center) {
                                Text("Narrated by ", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.align(Alignment.CenterVertically))
                                item.narrators.forEach { name ->
                                    Text(name, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.clickable(role = Role.Button) { actions.onNarrator(name) }.padding(4.dp).testTag("narrator-$name"))
                                }
                            }
                        }
                        metadata.series.forEach { series ->
                            Text("Series: ${series.name}" + (series.sequence?.let { " #$it" } ?: ""), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.clickable(role = Role.Button) { actions.onSeries(series.id, series.name) }.padding(vertical = 4.dp).testTag("series-${series.id}"))
                        }
                        val facts = listOfNotNull(
                            item.duration.takeIf { it > 0 && !item.isPodcast }?.let { formatDuration(it) },
                            metadata.publishedYear, metadata.publisher, metadata.language,
                            item.media.numEpisodes?.let { "$it episodes" },
                        )
                        if (facts.isNotEmpty()) Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (progress != null && (progress.progress > 0 || progress.isFinished)) {
                            val text = if (progress.isFinished) stringResource(R.string.finished) else "${(progress.progress * 100).toInt()}% listened · ${formatDuration((progress.duration - progress.currentTime).coerceAtLeast(0.0))} left"
                            Column(Modifier.semantics(mergeDescendants = true) {}.testTag("item-progress"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(text, style = MaterialTheme.typography.labelLarge)
                                ProgressLine(if (progress.isFinished) 1.0 else progress.progress)
                            }
                        }
                        primary()
                    }
                }
                if (wide) {
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), modifier = Modifier.padding(top = 8.dp)) {
                        Cover(coverUrl, item.title, Modifier.width(260.dp), podcast = item.isPodcast)
                        Box(Modifier.weight(1f)) { header() }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 8.dp)) {
                        Cover(coverUrl, item.title, Modifier.widthIn(max = 280.dp).fillMaxWidth(0.72f), podcast = item.isPodcast)
                        Box(Modifier.fillMaxWidth()) { header() }
                    }
                }
            }
            item { extra() }
            if (metadata.genres.isNotEmpty()) item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    metadata.genres.forEach { genre -> AssistChip(onClick = { actions.onGenre(genre) }, label = { Text(genre) }, modifier = Modifier.testTag("genre-$genre")) }
                }
            }
            description?.let { text -> item { ExpandableText(text) } }
            more()
            val chapters = item.media.chapters
            if (chapters.isNotEmpty()) {
                item { Text(stringResource(R.string.chapters), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() }) }
                itemsIndexed(chapters) { index, chapter ->
                    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("chapter-$index"), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(chapter.title.ifBlank { "Chapter ${index + 1}" }, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                        Text(formatClock(chapter.start), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
fun ExpandableText(text: String) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(text, style = MaterialTheme.typography.bodyMedium, maxLines = if (expanded) Int.MAX_VALUE else 6, modifier = Modifier.testTag("item-description"))
        if (text.length > 280) TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) stringResource(R.string.action_show_less) else stringResource(R.string.action_show_more)) }
    }
}
