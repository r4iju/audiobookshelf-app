package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ListeningDurabilityJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun listenedOnServer(itemId: String) = Fixture.observations().getJSONArray("localSessions").objects()
        .filter { it.getString("libraryItemId") == itemId }.sumOf { it.optDouble("timeListening", 0.0) }

    @Test
    fun listeningWhoseWriteFailsAsTheTitleStopsIsKeptUntilStorageRecovers() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        val files = InstrumentationRegistry.getInstrumentation().targetContext.filesDir
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.scrollTo("catalog-grid", "item-book-2")
            compose.tap("item-book-2")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.waitUntil(10_000) { compose.shownSeconds() >= 0 }
            val start = compose.shownSeconds()
            compose.waitForSeconds(start + 4)
            try {
                // Device storage refuses writes exactly while the title is stopped and handed back.
                check(files.setWritable(false, false))
                compose.tap("player-close")
                Thread.sleep(2_000)
            } finally {
                files.setWritable(true, true)
            }
            eventually(30_000) { listenedOnServer("book-2") >= 3.0 }
        }
    }
}
