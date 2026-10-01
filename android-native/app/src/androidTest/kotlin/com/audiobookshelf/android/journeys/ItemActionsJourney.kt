package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ItemActionsJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun actions() = JSONObject(Fixture.get("${Fixture.server}/__android__/actions"))

    @Test
    fun anAdministratorOpensAndClosesAnItemFeed() {
        Fixture.resetAppData()
        Fixture.configure("podcast-admin")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("rss-feed")
            compose.replaceText("feed-slug", "evening-reads")
            compose.tap("feed-open")
            compose.waitForTag("feed-url")
            compose.onNodeWithTag("feed-url").assertTextContains("/feed/evening-reads", substring = true)
            val feeds = actions().getJSONArray("feeds").objects()
            assertEquals(listOf("evening-reads"), feeds.map { it.getString("slug") })
            assertEquals("book-0", feeds.single().getString("entityId"))
            compose.capture("item-feed-open")

            compose.tap("feed-close")
            eventually { actions().getJSONArray("feeds").length() == 0 }
            compose.waitUntil(5_000) { !compose.isShown("feed-url") }
        }
    }

    @Test
    fun aListenerSeesAnOpenFeedButCannotOpenOrCloseOne() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-1")
            compose.waitForTag("play")
            assertFalse("Only administrators may open a feed", compose.isShown("rss-feed"))
            compose.pressBack()

            Fixture.post("${Fixture.server}/__android__/open-feed", """{"itemId":"book-0","slug":"shared"}""")
            compose.tap("item-book-0")
            compose.tap("rss-feed")
            compose.waitForTag("feed-url")
            compose.onNodeWithTag("feed-url").assertTextContains("/feed/shared", substring = true)
            assertFalse("Only administrators may close a feed", compose.isShown("feed-close"))
            assertFalse(compose.isShown("feed-open"))
        }
    }

    @Test
    fun anEbookIsSentToAConfiguredDeviceOnlyWhenOneExists() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.waitForTag("read-ebook")
            assertFalse("Without a configured e-reader there is nowhere to send to", compose.isShown("send-ebook"))
        }
        Fixture.post("${Fixture.server}/__android__/ereader-devices", """{"names":["Study Kindle","Kobo"]}""")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.tap("item-book-0")
            compose.tap("send-ebook")
            compose.tap("send-device-Kobo")
            compose.waitForTag("send-ebook-sent")
            val sent = actions().getJSONArray("sentEbooks").objects()
            assertEquals(listOf("book-0" to "Kobo"), sent.map { it.getString("libraryItemId") to it.getString("deviceName") })
            compose.capture("item-ebook-sent")
        }
    }

    @Test
    fun aRefusedDeliveryIsReportedAndNotShownAsSent() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        Fixture.post("${Fixture.server}/__android__/ereader-devices", """{"names":["Kobo"]}""")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("send-ebook")
            // The device is removed on the server after the app loaded it.
            Fixture.post("${Fixture.server}/__android__/ereader-devices", """{"names":[]}""")
            compose.tap("send-device-Kobo")
            compose.waitForTag("send-ebook-error")
            assertFalse(compose.isShown("send-ebook-sent"))
            assertTrue(actions().getJSONArray("sentEbooks").length() == 0)
        }
    }
}
