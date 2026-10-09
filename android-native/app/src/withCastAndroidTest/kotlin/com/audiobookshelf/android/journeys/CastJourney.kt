package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.hasText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Discovery must leave phone playback intact, whether the network has receivers or not. */
@RunWith(AndroidJUnit4::class)
class CastJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun receiverDiscoveryLeavesPhonePlaybackRunning() {
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
            compose.waitUntil(30_000) {
                compose.isShown("cast-receiver") || compose.onAllNodes(hasText("No cast devices found")).fetchSemanticsNodes().isNotEmpty()
            }
            val shown = compose.shownSeconds()
            compose.tap("cast-close")
            compose.waitUntil(10_000) { !compose.isShown("cast-sheet") }

            compose.waitForTag("player-playing")
            compose.waitForSeconds(shown + 2)
        }
    }
}
