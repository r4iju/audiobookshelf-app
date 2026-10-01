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
        if (savedInstanceState == null) OpenIdSignIn.pending(this).handle(intent)
        setContent { AppRoot() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        OpenIdSignIn.pending(this).handle(intent)
    }

    override fun onResume() {
        super.onResume()
        // A callback intent arrives before onResume; only a return without one means the browser was closed.
        window.decorView.post { OpenIdSignIn.pending(this).resumed() }
    }
}
