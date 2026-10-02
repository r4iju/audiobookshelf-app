package com.audiobookshelf.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.SavedConnection
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph

@Composable
fun AccountsScreen(active: SessionState.Active, padding: PaddingValues) {
    val accounts = LocalContext.current.graph.accounts
    var removing by remember { mutableStateOf<SavedConnection?>(null) }
    Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
        SectionTitle("Signed in")
        ListItem(
            headlineContent = { Text(active.connection.credentials.username) },
            supportingContent = { Text(active.connection.credentials.server) },
            leadingContent = { Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary) },
            modifier = Modifier.testTag("active-account"),
        )
        val others = active.connections.filter { it.id != active.connection.id }
        if (others.isNotEmpty()) SectionTitle("Other accounts")
        others.forEach { saved ->
            ListItem(
                headlineContent = { Text(saved.credentials.username) },
                supportingContent = { Text(saved.credentials.server + if (saved.needsSignIn) " · sign in required" else "") },
                leadingContent = { Icon(Icons.Outlined.AccountCircle, null) },
                trailingContent = {
                    IconButton(onClick = { removing = saved }, modifier = Modifier.testTag("remove-account-${saved.credentials.username}")) {
                        Icon(Icons.Outlined.Delete, "Remove ${saved.credentials.username}")
                    }
                },
                modifier = Modifier
                    .clickable(role = Role.Button, onClickLabel = "Switch to this account") { accounts.switchTo(saved.id) }
                    .testTag("account-${saved.credentials.username}"),
            )
        }
        ListItem(
            headlineContent = { Text("Add account") },
            leadingContent = { Icon(Icons.Outlined.PersonAdd, null) },
            modifier = Modifier.clickable(role = Role.Button) { accounts.addAccount() }.testTag("add-account"),
        )
        ListItem(
            headlineContent = { Text("Sign out of ${active.connection.credentials.username}", color = MaterialTheme.colorScheme.error) },
            supportingContent = { Text("Removes this account from the device. Downloads and unsent listening for it stay until it signs in again.") },
            modifier = Modifier.clickable(role = Role.Button) { removing = active.connection }.testTag("sign-out"),
        )
        Text(
            "Each account keeps its own progress, downloads and library choice. Switching never mixes them.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(16.dp),
        )
    }
    removing?.let { target ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove ${target.credentials.username}?") },
            text = { Text("You can add the account again later. Its downloads and unsent listening stay on this device.") },
            confirmButton = { TextButton(onClick = { removing = null; accounts.remove(target.id) }, modifier = Modifier.testTag("confirm-remove")) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
        )
    }
}
