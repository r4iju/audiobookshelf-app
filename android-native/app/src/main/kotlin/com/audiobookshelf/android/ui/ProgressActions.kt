package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.core.MediaProgress
import kotlinx.coroutines.launch

/** Marks a title or episode finished or unfinished, and discards its progress on the server. */
@Composable
fun ProgressActions(itemId: String, episodeId: String?, active: SessionState.Active, catalog: CatalogModel, tagPrefix: String = "item", progressGeneration: Long? = null) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    val progress = catalog.progressFor(itemId, episodeId)
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf(false) }
    val finished = progress?.isFinished == true
    val resets by graph.resets.requested.collectAsState()
    val reset = resets.firstOrNull { it.matches(active.client.account, itemId, episodeId) }
    val discarding = reset != null
    val unanswered by graph.publications.attempts.collectAsState()
    val unreadable by graph.publications.unreadable.collectAsState()
    val uncertain = discarding && (unreadable || unanswered.any { it.holds(active.client.account, itemId, episodeId) })
    var confirmingAnyway by remember { mutableStateOf(false) }
    var wasDiscarding by remember { mutableStateOf(false) }
    // A discard completed in the background removes the progress shown here too.
    LaunchedEffect(discarding) {
        if (wasDiscarding && !discarding) catalog.forgetProgress(itemId, episodeId)
        wasDiscarding = discarding
    }

    fun run(action: suspend () -> Unit) {
        saving = true; error = null
        scope.launch {
            try { action() } catch (failure: Exception) {
                error = failure.localizedMessage ?: context.getString(R.string.item_not_saved_try_again); graph.accounts.handle(failure)
            } finally { saving = false }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(
            onClick = {
                run {
                    val item = catalog.items.firstOrNull { it.id == itemId }
                    val epoch = item?.progressGenerations?.get(episodeId.orEmpty()) ?: item?.progressGeneration ?: progressGeneration
                    val saved = graph.setFinished(active.client, itemId, episodeId, !finished, epoch)
                    catalog.applyProgress(saved ?: MediaProgress(libraryItemId = itemId, episodeId = episodeId, isFinished = !finished, progress = if (finished) 0.0 else 1.0))
                }
            },
            enabled = !saving && !discarding,
            modifier = Modifier.fillMaxWidth().testTag(if (finished) "$tagPrefix-unfinish" else "$tagPrefix-finish"),
        ) { Text(if (finished) stringResource(R.string.item_mark_unfinished) else stringResource(R.string.action_mark_finished)) }
        if (uncertain) {
            Text(stringResource(R.string.item_discard_uncertain),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("discard-uncertain"))
            if (!unreadable) TextButton(onClick = { confirmingAnyway = true }, enabled = !saving, modifier = Modifier.fillMaxWidth().testTag("discard-anyway")) { Text(stringResource(R.string.item_discard_anyway)) }
            if (reset?.observed == false) TextButton(onClick = {
                run { if (!graph.resolveUncertainDiscard(active.client, itemId, episodeId, discard = false)) error = context.getString(R.string.item_discard_under_way) }
            }, enabled = !saving, modifier = Modifier.fillMaxWidth().testTag("keep-progress")) { Text(stringResource(R.string.item_keep_progress)) }
        } else if (discarding) {
            Text(stringResource(R.string.item_discard_pending),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("discard-pending"))
        } else if (progress != null) {
            TextButton(onClick = { confirming = true }, enabled = !saving, modifier = Modifier.fillMaxWidth().testTag("discard-progress")) { Text(stringResource(R.string.action_discard_progress)) }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
    if (confirmingAnyway) AlertDialog(
        onDismissRequest = { confirmingAnyway = false },
        title = { Text(stringResource(R.string.item_discard_anyway_question)) },
        text = { Text(stringResource(R.string.item_discard_anyway_explanation)) },
        confirmButton = {
            TextButton(onClick = {
                confirmingAnyway = false
                run { graph.resolveUncertainDiscard(active.client, itemId, episodeId, discard = true) }
            }, modifier = Modifier.testTag("confirm-discard-anyway")) { Text(stringResource(R.string.item_discard)) }
        },
        dismissButton = { TextButton(onClick = { confirmingAnyway = false }) { Text(stringResource(R.string.action_cancel)) } },
    )
    if (confirming) AlertDialog(
        onDismissRequest = { confirming = false },
        title = { Text(stringResource(R.string.item_discard_progress_question)) },
        text = { Text(stringResource(R.string.item_discard_progress_explanation)) },
        confirmButton = {
            TextButton(onClick = {
                confirming = false
                run {
                    if (graph.discardProgress(active.client, itemId, episodeId)) catalog.forgetProgress(itemId, episodeId)
                }
            }, modifier = Modifier.testTag("confirm-discard-progress")) { Text(stringResource(R.string.item_discard)) }
        },
        dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.action_cancel)) } },
    )
}
