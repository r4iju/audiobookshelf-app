package com.audiobookshelf.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.R
import com.audiobookshelf.android.data.PagedItems
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.MediaProgress

@Composable
fun FilteredScreen(list: PagedItems, padding: PaddingValues, progressFor: (String) -> MediaProgress?, open: (LibraryItem) -> Unit) {
    val coverWidth = catalogCoverWidth()
    val state = rememberLazyGridState()
    LaunchedEffect(state, list) {
        snapshotFlow { state.layoutInfo.visibleItemsInfo.lastOrNull()?.index to state.layoutInfo.totalItemsCount }
            .collect { (last, count) -> if (last != null && last >= count - 4) list.loadMore() }
    }
    LazyVerticalGrid(
        GridCells.Adaptive(coverWidth), Modifier.fillMaxSize().padding(padding).testTag("filtered-items"), state,
        contentPadding = PaddingValues(ShelfSpacing.page), horizontalArrangement = Arrangement.spacedBy(ShelfSpacing.gap), verticalArrangement = Arrangement.spacedBy(ShelfSpacing.section),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Text(if (list.loading && list.items.isEmpty()) stringResource(R.string.grp_loading) else pluralStringResource(R.plurals.grp_title_count, list.total, list.total), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        items(list.items, key = { it.id }) { item -> ItemCard(item, progressFor(item.id), Modifier.fillMaxWidth()) { open(item) } }
        if (list.loading) item(span = { GridItemSpan(maxLineSpan) }) { Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        list.error?.let { error -> item(span = { GridItemSpan(maxLineSpan) }) { MessageState(stringResource(R.string.grp_titles_could_not_load), error, tag = "filtered-error", action = stringResource(R.string.action_retry), actionTag = "filtered-retry") { list.loadMore() } } }
        if (!list.loading && list.error == null && list.items.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { MessageState(stringResource(R.string.grp_nothing_here), null, tag = "filtered-empty") }
    }
}
