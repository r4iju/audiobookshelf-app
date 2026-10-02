package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The emulator network has no cast receiver, so this covers discovery's empty state, not a real cast. */
@RunWith(AndroidJUnit4::class)
class CastJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun withNoReceiverOnTheNetworkCastingExplainsWhyAndPhonePlaybackContinues() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.scrollTo("catalog-grid", "item-book-0")
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            compose.waitForSeconds(7)

            compose.tap("player-cast")
            compose.waitForTag("cast-sheet")
            compose.waitForText("Playing on this phone")
            compose.waitForText("No cast devices found", 30_000)
            compose.capture("cast-no-receivers")
            val shown = compose.shownSeconds()
            compose.tap("cast-close")
            compose.waitUntil(10_000) { !compose.isShown("cast-sheet") }

            compose.waitForTag("player-playing")
            compose.waitForSeconds(shown + 2)
        }
    }
}
