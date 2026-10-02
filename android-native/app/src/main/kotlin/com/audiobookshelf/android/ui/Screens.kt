package com.audiobookshelf.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import com.audiobookshelf.android.R
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow

/** Content shown under every pushed screen, used for the mini player. */
val LocalBottomAccessory = compositionLocalOf<@Composable () -> Unit> { {} }

/** Standard pushed screen: title bar with Back, so every route has the same navigation affordance. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RouteScaffold(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: @Composable (PaddingValues) -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack, modifier = Modifier.testTag("back")) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.grp_back)) } },
                actions = actions,
            )
        },
        bottomBar = { Column(Modifier.navigationBarsPadding()) { LocalBottomAccessory.current() } },
        content = content,
    )
}
