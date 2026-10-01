package com.audiobookshelf.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.audiobookshelf.android.auth.OpenIdSignIn
import com.audiobookshelf.android.ui.AppRoot

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        graph.playback
        graph.serverEvents
        graph.downloads.resumeInterrupted()
        graph.readingSync
        if (savedInstanceState == null) route(intent)
        setContent { AppRoot() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        route(intent)
    }

    private fun route(intent: Intent?) {
        if (OpenIdSignIn.pending(this).handle(intent)) return
        if (intent?.getBooleanExtra(EXTRA_OPEN_PLAYER, false) == true) graph.openPlayerRequests.tryEmit(Unit)
    }

    override fun onResume() {
        super.onResume()
        // A callback intent arrives before onResume; only a return without one means the browser was closed.
        window.decorView.post { OpenIdSignIn.pending(this).resumed() }
    }

    companion object {
        const val EXTRA_OPEN_PLAYER = "open-player"
    }
}
