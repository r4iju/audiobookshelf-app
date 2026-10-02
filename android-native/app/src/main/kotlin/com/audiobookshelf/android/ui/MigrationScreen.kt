package com.audiobookshelf.android.ui

import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.migration.Migration
import com.audiobookshelf.core.migration.Issue

/** Chooses an export of the previous app; a note says when an earlier import did not finish. */
@Composable
fun ImportLegacyButton(modifier: Modifier = Modifier) {
    val graph = LocalContext.current.graph
    val choose = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let(graph.migration::open) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        OutlinedButton(onClick = { choose.launch(arrayOf("*/*")) }, modifier = Modifier.fillMaxWidth().testTag("import-legacy")) {
            Text("Import from the previous app")
        }
        if (graph.migration.interrupted) {
            Text("An import did not finish. Choose the same export to continue where it stopped.", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("migration-interrupted"))
        }
    }
}

@Composable
fun MigrationScreen(step: Migration.Step) {
    val graph = LocalContext.current.graph
    val context = LocalContext.current
    val close = graph.migration::close
    BackHandler(enabled = step !is Migration.Step.Importing, onBack = close)
    val size: (Long) -> String = { Formatter.formatShortFileSize(context, it) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
      Column(Modifier.fillMaxSize().safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth().testTag("migration"),
            contentPadding = PaddingValues(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item {
                Text("Import from the previous app", style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().semantics { heading() })
            }
            when (step) {
                Migration.Step.Reading -> item { CircularProgressIndicator(Modifier.padding(24.dp)) }
                is Migration.Step.Refused -> {
                    item { Notice(step.message, "migration-refused", error = true) }
                }
                is Migration.Step.Already -> {
                    item { Notice("This export was already imported. Titles, listening and positions from it are on this device.", "migration-already") }
                }
                is Migration.Step.Ready -> {
                    val plan = step.plan
                    item {
                        Body("${step.name}\nThe previous app and this file are only read; nothing in them changes. Titles, listening and positions attach to an account once it signs in here. Passwords are not in the export, so each account signs in again.",
                            "migration-preflight")
                    }
                    item { Section("Accounts") }
                    items(plan.accounts) { account ->
                        Row(account.username, "${account.identity.server} · ${if (account.signedIn) "signed in" else "sign in after importing"}")
                    }
                    item { Section("Titles") }
                    items(plan.titles) { title ->
                        Row(title.title, size(title.bytes) + if (title.partial) " · the rest downloads again" else "", "migration-title-${title.itemId}")
                    }
                    if (plan.issues.isNotEmpty()) {
                        item { Section("Not imported") }
                        items(plan.issues) { issue -> IssueRow(issue) }
                    }
                    item {
                        Body("Needs ${size(plan.requiredBytes)}; ${size(plan.availableBytes)} free.", "migration-space")
                    }
                    if (!plan.fits) item { Notice("There is not enough free space on this device. Free some space, then choose the export again.", "migration-no-space", error = true) }
                }
                is Migration.Step.Importing -> {
                    item { Body("Copying files: ${step.copied} of ${step.total}. If the app closes, choose the same export again to continue.", "migration-progress") }
                    item { LinearProgressIndicator({ if (step.total == 0) 0f else step.copied.toFloat() / step.total }, Modifier.widthIn(max = 560.dp).fillMaxWidth()) }
                }
                is Migration.Step.Done -> {
                    val outcome = step.outcome
                    item { Notice("Imported ${outcome.titles.size} titles, ${outcome.sessions.size} listening sessions and ${outcome.progress.size} positions. Settings from the previous app were applied.", "migration-done") }
                    items(step.waiting) { account ->
                        Body("Sign in to ${account.identity.server} as ${account.username} to attach its titles, listening and positions.", "migration-waiting")
                    }
                    if (outcome.issues.isNotEmpty()) {
                        item { Section("Not imported") }
                        items(outcome.issues) { issue -> IssueRow(issue) }
                    }
                }
            }
        }
        // Kept in view below the list, so the next step never needs scrolling to find.
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            when (step) {
                is Migration.Step.Ready -> {
                    Button(onClick = graph.migration::start, enabled = step.plan.fits, modifier = Modifier.fillMaxWidth().height(52.dp).testTag("start-import")) { Text("Import") }
                    CloseButton("Cancel", close)
                }
                is Migration.Step.Done -> Button(onClick = close, modifier = Modifier.fillMaxWidth().height(52.dp).testTag("migration-close")) { Text("Continue") }
                is Migration.Step.Refused, is Migration.Step.Already -> CloseButton("Close", close)
                else -> Unit
            }
        }
      }
    }
}

@Composable
private fun Section(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(top = 8.dp).semantics { heading() })
}

@Composable
private fun Body(text: String, tag: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().testTag(tag))
}

@Composable
private fun Row(headline: String, supporting: String, tag: String? = null) {
    ListItem(headlineContent = { Text(headline) }, supportingContent = { Text(supporting) },
        modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().let { if (tag != null) it.testTag(tag) else it })
}

@Composable
private fun IssueRow(issue: Issue) = Row(issue.title ?: "Account", issue.detail, "migration-issue")

@Composable
private fun Notice(text: String, tag: String, error: Boolean = false) {
    Surface(color = if (error) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.medium,
        modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth()) {
        Text(text, Modifier.padding(14.dp).testTag(tag).semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun CloseButton(label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.testTag("migration-close")) { Text(label) }
}
