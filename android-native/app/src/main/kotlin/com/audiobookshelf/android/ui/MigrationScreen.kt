package com.audiobookshelf.android.ui

import android.text.format.Formatter
import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
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
            Text(stringResource(R.string.set_import_previous_app))
        }
        if (graph.migration.interrupted) {
            Text(stringResource(R.string.set_import_interrupted), style = MaterialTheme.typography.bodyMedium,
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
                Text(stringResource(R.string.set_import_previous_app), style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().semantics { heading() })
            }
            when (step) {
                Migration.Step.Reading -> item { CircularProgressIndicator(Modifier.padding(24.dp)) }
                is Migration.Step.Refused -> {
                    item { Notice(step.message, "migration-refused", error = true) }
                }
                is Migration.Step.Already -> {
                    item { Notice(stringResource(R.string.set_import_already), "migration-already") }
                }
                is Migration.Step.Ready -> {
                    val plan = step.plan
                    item {
                        Body(stringResource(R.string.set_import_preflight, step.name),
                            "migration-preflight")
                    }
                    item { Section(stringResource(R.string.title_accounts)) }
                    items(plan.accounts) { account ->
                        Row(account.username, if (account.signedIn) stringResource(R.string.set_import_account_signed_in, account.identity.server) else stringResource(R.string.set_import_account_sign_in_later, account.identity.server))
                    }
                    item { Section(stringResource(R.string.set_import_titles)) }
                    items(plan.titles) { title ->
                        Row(title.title, if (title.partial) stringResource(R.string.set_import_title_partial, size(title.bytes)) else size(title.bytes), "migration-title-${title.itemId}")
                    }
                    if (plan.issues.isNotEmpty()) {
                        item { Section(stringResource(R.string.set_not_imported)) }
                        items(plan.issues) { issue -> IssueRow(issue) }
                    }
                    item {
                        Body(stringResource(R.string.set_import_space, size(plan.requiredBytes), size(plan.availableBytes)), "migration-space")
                    }
                    if (!plan.fits) item { Notice(stringResource(R.string.set_import_no_space), "migration-no-space", error = true) }
                }
                is Migration.Step.Importing -> {
                    item { Body(stringResource(R.string.set_import_progress, step.copied, step.total), "migration-progress") }
                    item { LinearProgressIndicator({ if (step.total == 0) 0f else step.copied.toFloat() / step.total }, Modifier.widthIn(max = 560.dp).fillMaxWidth()) }
                }
                is Migration.Step.Done -> {
                    val outcome = step.outcome
                    item { Notice(stringResource(R.string.set_import_done, outcome.titles.size, outcome.sessions.size, outcome.progress.size), "migration-done") }
                    items(step.waiting) { account ->
                        Body(stringResource(R.string.set_import_waiting, account.identity.server, account.username), "migration-waiting")
                    }
                    if (outcome.issues.isNotEmpty()) {
                        item { Section(stringResource(R.string.set_not_imported)) }
                        items(outcome.issues) { issue -> IssueRow(issue) }
                    }
                }
            }
        }
        // Kept in view below the list, so the next step never needs scrolling to find.
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            when (step) {
                is Migration.Step.Ready -> {
                    Button(onClick = graph.migration::start, enabled = step.plan.fits, modifier = Modifier.fillMaxWidth().height(52.dp).testTag("start-import")) { Text(stringResource(R.string.set_import)) }
                    CloseButton(stringResource(R.string.action_cancel), close)
                }
                is Migration.Step.Done -> Button(onClick = close, modifier = Modifier.fillMaxWidth().height(52.dp).testTag("migration-close")) { Text(stringResource(R.string.set_continue)) }
                is Migration.Step.Refused, is Migration.Step.Already -> CloseButton(stringResource(R.string.set_close), close)
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
private fun IssueRow(issue: Issue) = Row(issue.title ?: stringResource(R.string.set_import_issue_account), issue.detail, "migration-issue")

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
