package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReadingListeningJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun aPageReadWhileListeningIsUnsentNeverSupersedesThatListening() {
        Fixture.resetAppData()
        Fixture.configure("pdf-audio")
        Fixture.refuseListening(true)
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("play")
            compose.waitForTag("player-playing", 15_000)
            compose.waitUntil(10_000) { compose.shownSeconds() >= 0 }
            val start = compose.shownSeconds()
            compose.waitForSeconds(start + 4)
            compose.tap("player-close")
            // Well past any clock difference between the emulator and the server.
            Thread.sleep(3_000)
            compose.tap("read-ebook")
            compose.waitForText("Page 1 of 4")
            compose.tap("pdf-next")
            compose.waitForText("Page 2 of 4")
            // The page is read while the server still refuses the listening that came before it.
            Thread.sleep(3_000)
            Fixture.refuseListening(false)
            runCatching {
                eventually(90_000) {
                    val progress = Fixture.serverProgress("book-0")
                    progress != null && progress.optDouble("currentTime") >= start + 3 && progress.optString("ebookLocation") == "2"
                }
            }.onFailure {
                val sent = Fixture.observations().getJSONArray("localSessions").objects().map { it.optDouble("currentTime") to it.optDouble("updatedAt") }
                throw AssertionError("Listened from $start; server holds ${Fixture.serverProgress("book-0")}; listening sent $sent", it)
            }
        }
    }
}
