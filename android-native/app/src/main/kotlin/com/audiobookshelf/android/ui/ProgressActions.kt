package com.audiobookshelf.android.ui

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
fun ProgressActions(itemId: String, episodeId: String?, active: SessionState.Active, catalog: CatalogModel, tagPrefix: String = "item") {
    val graph = LocalContext.current.graph
    val scope = rememberCoroutineScope()
    val progress = catalog.progressFor(itemId, episodeId)
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf(false) }
    val finished = progress?.isFinished == true
    val resets by graph.resets.requested.collectAsState()
    val discarding = resets.any { it.matches(active.client.account, itemId, episodeId) }
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
                error = failure.message ?: "Not saved. Try again."; graph.accounts.handle(failure)
            } finally { saving = false }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(
            onClick = {
                run {
                    val saved = active.client.setFinished(itemId, episodeId, !finished)
                    catalog.applyProgress(saved ?: MediaProgress(libraryItemId = itemId, episodeId = episodeId, isFinished = !finished, progress = if (finished) 0.0 else 1.0))
                }
            },
            enabled = !saving && !discarding,
            modifier = Modifier.fillMaxWidth().testTag(if (finished) "$tagPrefix-unfinish" else "$tagPrefix-finish"),
        ) { Text(if (finished) "Mark unfinished" else "Mark finished") }
        if (discarding) {
            Text("Discarding progress. This finishes once your server can be reached and this title's listening is sent.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("discard-pending"))
        } else if (progress != null) {
            TextButton(onClick = { confirming = true }, enabled = !saving, modifier = Modifier.fillMaxWidth().testTag("discard-progress")) { Text("Discard progress") }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
    if (confirming) AlertDialog(
        onDismissRequest = { confirming = false },
        title = { Text("Discard progress?") },
        text = { Text("Your position and finished state for this title are removed from the server for every device.") },
        confirmButton = {
            TextButton(onClick = {
                confirming = false
                run {
                    if (graph.discardProgress(active.client, itemId, episodeId)) catalog.forgetProgress(itemId, episodeId)
                }
            }, modifier = Modifier.testTag("confirm-discard-progress")) { Text("Discard") }
        },
        dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
    )
}
