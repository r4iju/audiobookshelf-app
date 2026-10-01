package com.audiobookshelf.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.viewmodel.compose.viewModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph

@Composable
fun AppRoot() {
    val graph = LocalContext.current.graph
    val settings by graph.settings.settings.collectAsState()
    val session by graph.accounts.session.collectAsState()
    AbsTheme(settings.appearance) {
        when (val state = session) {
            SessionState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            is SessionState.SignedOut -> ConnectScreen(state)
            is SessionState.Active -> SignedIn(state)
        }
    }
}

@Composable
private fun SignedIn(active: SessionState.Active) {
    val model: MainViewModel = viewModel()
    val catalog = model.catalogFor(active)
    val route = model.stack.lastOrNull()
    BackHandler(enabled = route != null) { model.pop() }
    when (route) {
        null -> Scaffold(
            topBar = {
                LibraryTopBar(catalog) {
                    IconButton(onClick = { model.push(Route.Settings) }, modifier = Modifier.testTag("open-settings")) { Icon(Icons.Outlined.Settings, "Settings") }
                }
            },
        ) { padding -> LibraryScreen(catalog, padding, open = { model.push(Route.Item(it.id)) }) }
        else -> LaunchedEffect(route) { model.pop() }
    }
}
