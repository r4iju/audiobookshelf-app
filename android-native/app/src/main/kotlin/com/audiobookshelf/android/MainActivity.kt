package com.audiobookshelf.android

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.audiobookshelf.android.data.Orientation
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import com.audiobookshelf.android.auth.OpenIdSignIn
import com.audiobookshelf.android.ui.AppRoot

class MainActivity : ComponentActivity() {
    var readerVolumeNavigation: ((Int) -> Boolean)? = null
    private val readerVolumeKeys = mutableSetOf<Int>()
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.keyCode in setOf(android.view.KeyEvent.KEYCODE_VOLUME_UP, android.view.KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == android.view.KeyEvent.ACTION_UP && readerVolumeKeys.remove(event.keyCode)) return true
            if (event.action == android.view.KeyEvent.ACTION_DOWN) {
                if (event.keyCode in readerVolumeKeys) return true
                if (event.repeatCount == 0 && readerVolumeNavigation?.invoke(event.keyCode) == true) {
                    readerVolumeKeys.add(event.keyCode)
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        graph.playback
        graph.serverEvents
        graph.downloads.resumeInterrupted()
        graph.readingSync
        graph.startResets()
        graph.migration.attachSignedIn()
        if (savedInstanceState == null) route(intent)
        // Applied before the first frame so a locked orientation never flashes the other way at launch.
        applyOrientation(graph.settings.current.lockOrientation)
        lifecycleScope.launch { graph.settings.settings.map { it.lockOrientation }.distinctUntilChanged().collect(::applyOrientation) }
        setContent { AppRoot() }
    }

    private fun applyOrientation(lock: Orientation) {
        requestedOrientation = when (lock) {
            Orientation.NONE -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            Orientation.PORTRAIT -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            Orientation.LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        route(intent)
    }

    private fun route(intent: Intent?) {
        if (OpenIdSignIn.pending(this).handle(intent)) return
        if (intent?.getBooleanExtra(EXTRA_OPEN_PLAYER, false) == true) graph.openPlayerRequests.tryEmit(Unit)
        if (intent?.action == Intent.ACTION_VIEW && intent.data?.scheme == "content") graph.migration.open(intent.data!!)
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
