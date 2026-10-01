package com.audiobookshelf.android.ui

import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material.icons.outlined.Podcasts
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import kotlin.math.roundToInt

/**
 * Square artwork frame: tall, wide and missing covers all occupy the same box so grids and
 * shelves stay aligned. Missing or failed artwork shows a readable title placeholder.
 */
@Composable
fun Cover(model: Any?, title: String, modifier: Modifier = Modifier, podcast: Boolean = false) {
    var failed by remember(model) { mutableStateOf(model == null) }
    Box(
        modifier
            .aspectRatio(1f)
            .clip(CoverShape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        if (failed) {
            Column(Modifier.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Icon(if (podcast) Icons.Outlined.Podcasts else Icons.Outlined.Headphones, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(title, style = MaterialTheme.typography.labelMedium, maxLines = 3, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
            }
        } else {
            AsyncImage(model = model, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize(), onError = { failed = true })
        }
    }
}

@Composable
fun ProgressLine(fraction: Double, modifier: Modifier = Modifier) {
    LinearProgressIndicator(
        progress = { fraction.toFloat().coerceIn(0f, 1f) },
        modifier = modifier.fillMaxWidth().height(4.dp).clip(MaterialTheme.shapes.small),
        trackColor = MaterialTheme.colorScheme.surfaceVariant,
        gapSize = 0.dp,
        drawStopIndicator = {},
    )
}

@Composable
fun MessageState(title: String, message: String?, modifier: Modifier = Modifier, icon: ImageVector = Icons.Outlined.Info, tag: String? = null, action: String? = null, actionTag: String? = null, onAction: (() -> Unit)? = null) {
    Column(
        modifier.fillMaxWidth().padding(32.dp).let { if (tag != null) it.testTag(tag) else it },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        if (message != null) Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (action != null && onAction != null) {
            Button(onClick = onAction, modifier = if (actionTag != null) Modifier.testTag(actionTag) else Modifier) { Text(action) }
        }
    }
}

fun formatDuration(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "--"
    val total = seconds.roundToInt()
    val hours = total / 3600
    val minutes = total % 3600 / 60
    return when {
        hours > 0 -> "${hours}h ${minutes}m"
        minutes > 0 -> "${minutes}m"
        else -> "${total}s"
    }
}

fun formatClock(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "0:00"
    val total = seconds.toLong()
    val hours = total / 3600
    val minutes = total % 3600 / 60
    val secs = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs)
}

fun Modifier.describe(text: String) = semantics { contentDescription = text }

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}
