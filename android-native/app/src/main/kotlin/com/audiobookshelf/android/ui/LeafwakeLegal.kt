package com.audiobookshelf.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

@Composable
fun LeafwakeLegal() {
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    var document by remember { mutableStateOf<String?>(null) }
    Column {
        Text("Leafwake is an independent Audiobookshelf client. It is not affiliated with or endorsed by Audiobookshelf.")
        OutlinedButton(onClick = { document = "privacy.txt" }, modifier = Modifier.fillMaxWidth().testTag("leafwake-privacy")) { Text("Privacy policy") }
        OutlinedButton(onClick = { document = "licenses.txt" }, modifier = Modifier.fillMaxWidth().testTag("leafwake-licenses")) { Text("Open source licenses") }
        TextButton(onClick = { uri.openUri("https://github.com/r4iju/audiobookshelf-app/issues") }) { Text("Support") }
    }
    document?.let { name ->
        val text = remember(name) { context.assets.open("leafwake/$name").bufferedReader().use { it.readText() } }
        AlertDialog(onDismissRequest = { document = null },
            title = { Text(if (name == "privacy.txt") "Privacy policy" else "Open source licenses") },
            text = { Text(text, modifier = Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = { document = null }) { Text("Close") } },
            dismissButton = { TextButton(onClick = { uri.openUri(com.audiobookshelf.android.BuildConfig.SOURCE_URL) }) { Text("Source code") } })
    }
}
