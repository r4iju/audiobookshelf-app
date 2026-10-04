package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cast
import androidx.compose.material.icons.outlined.CastConnected
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import com.audiobookshelf.android.playback.CastRoutes
import kotlinx.coroutines.delay

@Composable
fun CastButton(casting: CastRoutes, onClick: () -> Unit) {
    if (!com.audiobookshelf.android.BuildConfig.CAST_ENABLED) return
    val status by casting.status.collectAsState()
    IconButton(onClick = onClick, modifier = Modifier.testTag("player-cast")) {
        val connectedTo = status.connectedTo
        if (connectedTo != null) Icon(Icons.Outlined.CastConnected, stringResource(R.string.cast_casting_to, connectedTo), tint = MaterialTheme.colorScheme.primary)
        else Icon(Icons.Outlined.Cast, stringResource(R.string.cast_cast))
    }
}

/** Where playback is heard, shown under the title while casting or after a cast problem. */
@Composable
fun CastLine(casting: CastRoutes) {
    val status by casting.status.collectAsState()
    status.connectedTo?.let { Text(stringResource(R.string.cast_playing_on, it), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.testTag("cast-playing-on")) }
    status.problem?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 4.dp).testTag("cast-problem")) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CastSheet(casting: CastRoutes, onDismiss: () -> Unit) {
    val status by casting.status.collectAsState()
    DisposableEffect(casting) {
        casting.startLooking()
        onDispose { casting.stopLooking() }
    }
    // Discovery reports receivers as it finds them; an empty list only means something after a while.
    var searched by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(SEARCH_MS); searched = true }

    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.testTag("cast-sheet")) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.cast_cast), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Text(status.connectedTo?.let { stringResource(R.string.cast_playing_on, it) } ?: status.connecting?.let { stringResource(R.string.cast_connecting_to, it) } ?: stringResource(R.string.cast_playing_on_phone),
                style = MaterialTheme.typography.bodyLarge)
            status.problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
            when {
                status.unavailable != null -> Text(status.unavailable!!, style = MaterialTheme.typography.bodyMedium)
                status.connectedTo != null -> Button(onClick = { casting.disconnect(); onDismiss() }, modifier = Modifier.testTag("cast-stop")) { Text(stringResource(R.string.cast_stop)) }
                status.receivers.isNotEmpty() -> status.receivers.forEach { receiver ->
                    ListItem(
                        headlineContent = { Text(receiver.name) },
                        supportingContent = receiver.description?.takeIf { it.isNotBlank() }?.let { { Text(it) } },
                        leadingContent = { Icon(Icons.Outlined.Tv, null) },
                        modifier = Modifier.fillMaxWidth().clickable { casting.connect(receiver.id) }.testTag("cast-receiver"),
                    )
                }
                !searched -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.cast_looking), style = MaterialTheme.typography.bodyMedium)
                }
                else -> Text(stringResource(R.string.cast_none_found),
                    style = MaterialTheme.typography.bodyMedium)
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End).testTag("cast-close")) { Text(stringResource(R.string.cast_close)) }
        }
    }
}

private const val SEARCH_MS = 8_000L
