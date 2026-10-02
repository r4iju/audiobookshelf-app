package com.audiobookshelf.android.ui

import com.audiobookshelf.android.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.auth.OpenIdSignIn
import com.audiobookshelf.core.AuthApi
import com.audiobookshelf.core.ServerAddress
import com.audiobookshelf.core.ServerStatus
import kotlinx.coroutines.launch

@Composable
fun ConnectScreen(state: SessionState.SignedOut) {
    val graph = LocalContext.current.graph
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val reauth = state.reauth
    var address by rememberSaveable { mutableStateOf(reauth?.credentials?.server ?: "") }
    var username by rememberSaveable { mutableStateOf(reauth?.credentials?.username ?: "") }
    var password by remember { mutableStateOf("") }
    var server by remember { mutableStateOf<Pair<ServerAddress, ServerStatus>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var connectionError by remember { mutableStateOf<String?>(null) }
    var signInError by remember { mutableStateOf<String?>(null) }
    val openId = remember { OpenIdSignIn.pending(context) }

    fun connect() {
        busy = true; connectionError = null
        scope.launch {
            try {
                server = graph.accounts.probe(address)
            } catch (error: Exception) {
                connectionError = error.localizedMessage
            } finally { busy = false }
        }
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (state.adding) {
                Row(Modifier.fillMaxWidth()) {
                    TextButton(onClick = { openId.clear(); graph.accounts.cancelAddAccount() }, modifier = Modifier.testTag("cancel-add-account")) { Text(stringResource(R.string.action_cancel)) }
                }
            } else Spacer(Modifier.height(48.dp))
            Column(Modifier.widthIn(max = 480.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.primaryContainer) {
                    Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Outlined.LibraryBooks, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.primary)
                    }
                }
                Text(if (state.adding) stringResource(R.string.set_add_an_account) else "Audiobookshelf", style = MaterialTheme.typography.headlineMedium)
                Text(stringResource(R.string.set_connect_intro), color = MaterialTheme.colorScheme.onSurfaceVariant)
                state.notice?.let {
                    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.medium) {
                        Text(it, Modifier.padding(14.dp).testTag("session-notice"), style = MaterialTheme.typography.bodyMedium)
                    }
                }
                val connected = server
                if (connected == null) {
                    OutlinedTextField(
                        value = address, onValueChange = { address = it; connectionError = null },
                        label = { Text(stringResource(R.string.server_address)) }, placeholder = { Text("https://books.example.com/abs") },
                        shape = MaterialTheme.shapes.medium, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("server-address"),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go, autoCorrectEnabled = false),
                        keyboardActions = KeyboardActions(onGo = { connect() }),
                        isError = connectionError != null,
                    )
                    connectionError?.let { ErrorText(it, "connection-error") }
                    Button(onClick = ::connect, enabled = !busy && address.isNotBlank(), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("connect")) {
                        if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp) else Text(stringResource(R.string.connect))
                    }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { server = null; signInError = null }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.set_change_server)) }
                        Text(connected.first.canonical, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if ("local" in connected.second.authMethods) {
                        OutlinedTextField(username, { username = it; signInError = null }, label = { Text(stringResource(R.string.username)) }, shape = MaterialTheme.shapes.medium, singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("username"),
                            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Next))
                        OutlinedTextField(password, { password = it; signInError = null }, label = { Text(stringResource(R.string.password)) }, shape = MaterialTheme.shapes.medium, singleLine = true,
                            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth().testTag("password"),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done))
                        signInError?.let { ErrorText(it, "sign-in-error") }
                        Button(
                            onClick = {
                                busy = true; signInError = null
                                scope.launch {
                                    try {
                                        graph.accounts.signIn(connected.first, username, password)
                                    } catch (error: AuthApi.LoginRejected) {
                                        signInError = error.localizedMessage
                                    } catch (error: Exception) {
                                        signInError = error.localizedMessage
                                    } finally { busy = false; password = "" }
                                }
                            },
                            enabled = !busy && username.isNotBlank(),
                            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("sign-in"),
                        ) { if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp) else Text(stringResource(R.string.set_sign_in)) }
                    }
                    if ("openid" in connected.second.authMethods) {
                        OutlinedButton(
                            onClick = { openId.start(connected.first, context) },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("openid-sign-in"),
                        ) { Text(stringResource(R.string.set_sign_in_openid)) }
                    }
                }
                openId.error?.let { ErrorText(it, "openid-error") }
                if (!state.adding) ImportLegacyButton()
                if (state.connections.isNotEmpty()) {
                    HorizontalDivider(Modifier.padding(vertical = 8.dp))
                    Text(stringResource(R.string.set_saved_accounts), style = MaterialTheme.typography.titleMedium)
                    state.connections.filter { it.id != reauth?.id }.forEach { saved ->
                        ListItem(
                            headlineContent = { Text(saved.credentials.username) },
                            supportingContent = { Text(if (saved.needsSignIn) stringResource(R.string.set_server_sign_in_required, saved.credentials.server) else saved.credentials.server) },
                            leadingContent = { Icon(Icons.Outlined.AccountCircle, null) },
                            trailingContent = { if (!saved.needsSignIn) TextButton(onClick = { graph.accounts.switchTo(saved.id) }, modifier = Modifier.testTag("use-account-${saved.credentials.username}")) { Text(stringResource(R.string.set_use_account)) } },
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun ErrorText(message: String, tag: String) {
    Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.testTag(tag).semantics { liveRegion = LiveRegionMode.Polite })
}
