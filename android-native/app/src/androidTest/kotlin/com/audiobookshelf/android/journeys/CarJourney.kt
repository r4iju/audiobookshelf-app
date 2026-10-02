package com.audiobookshelf.android.journeys

import android.content.ComponentName
import android.content.Intent
import android.media.browse.MediaBrowser
import android.media.session.MediaController
import android.media.session.PlaybackState
import android.os.Bundle
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.audiobookshelf.android.MainActivity
import com.audiobookshelf.android.playback.PlaybackService
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * The car's side of Android Auto: the platform media browser protocol the car head unit uses, driven
 * without touching the phone's screen once signed in. A physical car is not part of this check.
 */
@RunWith(AndroidJUnit4::class)
class CarJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private var browser: MediaBrowser? = null

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    private fun connect(): MediaBrowser {
        val connected = LinkedBlockingQueue<Boolean>()
        lateinit var created: MediaBrowser
        main {
            created = MediaBrowser(instrumentation.targetContext, ComponentName(instrumentation.targetContext, PlaybackService::class.java), object : MediaBrowser.ConnectionCallback() {
                override fun onConnected() { connected.offer(true) }
                override fun onConnectionFailed() { connected.offer(false) }
            }, null)
            created.connect()
        }
        check(connected.poll(20, TimeUnit.SECONDS) == true) { "The car could not connect to the media service" }
        return created.also { browser = it }
    }

    @After fun disconnect() { browser?.let { main { it.disconnect() } } }

    private fun MediaBrowser.children(id: String): List<MediaBrowser.MediaItem> {
        val loaded = LinkedBlockingQueue<List<MediaBrowser.MediaItem>>()
        val callback = object : MediaBrowser.SubscriptionCallback() {
            override fun onChildrenLoaded(parentId: String, children: List<MediaBrowser.MediaItem>) { loaded.offer(children) }
            override fun onError(parentId: String) { loaded.offer(emptyList()) }
        }
        main { subscribe(id, callback) }
        val children = loaded.poll(30, TimeUnit.SECONDS) ?: throw AssertionError("$id never loaded")
        main { unsubscribe(id, callback) }
        return children
    }

    private val MediaBrowser.MediaItem.title get() = description.title.toString()

    /** Follows entries by their shown titles from the root, as a driver would tap them. */
    private fun MediaBrowser.open(vararg titles: String): List<MediaBrowser.MediaItem> {
        var children = children(root)
        for (title in titles) {
            val next = children.firstOrNull { it.title == title } ?: throw AssertionError("\"$title\" is not among ${children.map { it.title }}")
            assertTrue("\"$title\" opens", next.isBrowsable)
            children = children(next.mediaId!!)
        }
        return children
    }

    private fun MediaBrowser.titles(vararg path: String) = open(*path).map { it.title }

    private fun MediaBrowser.controller() = MediaController(instrumentation.targetContext, sessionToken)

    private fun MediaController.waitUntilPlaying() = eventually(20_000) { playbackState?.state == PlaybackState.STATE_PLAYING }

    private fun signIn(mode: String = "baseline") {
        Fixture.resetAppData()
        Fixture.configure(mode)
        ActivityScenario.launch(MainActivity::class.java).use { compose.signIn() }
    }

    private fun played(itemId: String, after: Int = 0) = Fixture.requests().drop(after).any { it.getString("path") == "/api/items/$itemId/play" }

    @Test
    fun aCarBrowsesTheLibraryAndPlaysWithoutThePhone() {
        signIn()
        val car = connect()
        assertEquals(listOf("Continue", "Recent", "Libraries", "Downloads"), car.titles())
        val resuming = car.open("Continue").first { it.title == "Stories for Tomorrow 01" }
        assertEquals("Progress shows on titles in progress", 1, resuming.description.extras?.getInt("android.media.extra.PLAYBACK_STATUS"))
        assertEquals(listOf("Audiobooks", "Podcasts"), car.titles("Libraries"))
        assertEquals(listOf("Authors", "Series", "Collections"), car.titles("Libraries", "Audiobooks"))
        assertEquals(listOf("Stories for Tomorrow 03", "Stories for Tomorrow 02"), car.titles("Libraries", "Audiobooks", "Collections", "Evening shelf"))
        val authors = car.titles("Libraries", "Audiobooks", "Authors")
        assertEquals("Every author is listed under the grouping limit", 31, authors.size)
        val byAuthor = car.open("Libraries", "Audiobooks", "Authors", "Audiobookshelf QA")
        assertTrue("An author's series is one entry", byAuthor.any { it.title == "Tomorrow Trilogy" && it.isBrowsable })
        assertEquals(listOf("The Morning After", "A Quiet Evening"), car.titles("Libraries", "Podcasts", "Evening Stories"))
        assertEquals(listOf("Recently Added"), car.titles("Recent", "Audiobooks"))

        val series = car.open("Libraries", "Audiobooks", "Series", "Tomorrow Trilogy")
        assertEquals(listOf("1. Stories for Tomorrow 06", "2. Stories for Tomorrow 07", "10. Stories for Tomorrow 05"), series.map { it.title })
        val controller = car.controller()
        main { controller.transportControls.playFromMediaId(series.first().mediaId, Bundle()) }
        controller.waitUntilPlaying()
        assertTrue("The first book of the series plays", played("book-5"))
        main { controller.transportControls.pause() }
    }

    @Test
    fun groupingLimitAndSeriesOrderFollowTheSettings() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("open-settings")
            for (tag in listOf("car-grouping-25", "car-series-order-desc")) {
                compose.scrollTo("settings", tag)
                compose.tap(tag)
            }
        }
        val car = connect()
        val groups = car.open("Libraries", "Audiobooks", "Authors")
        assertEquals(listOf("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "Z"), groups.map { it.title })
        assertTrue("Groups open", groups.all { it.isBrowsable })
        assertEquals(listOf("Ada Ellison", "Alan Rook", "Amara Hale", "Arlo Penn", "Audiobookshelf QA", "Avery Stone"), car.titles("Libraries", "Audiobooks", "Authors", "A"))
        assertEquals(listOf("10. Stories for Tomorrow 05", "2. Stories for Tomorrow 07", "1. Stories for Tomorrow 06"), car.titles("Libraries", "Audiobooks", "Series", "Tomorrow Trilogy"))
    }

    @Test
    fun downloadedTitlesPlayInTheCarWithoutTheServer() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            compose.tap("item-book-0")
            compose.tap("download")
            compose.waitForTag("downloaded", 45_000)
        }
        Fixture.configure("offline-library")
        val start = Fixture.requests().size
        val car = connect()
        val downloaded = car.open("Downloads").single()
        assertEquals("Stories for Tomorrow 01", downloaded.title)
        assertEquals("Shown as downloaded", 2L, downloaded.description.extras?.getLong("android.media.extra.DOWNLOAD_STATUS"))
        val controller = car.controller()
        main { controller.transportControls.playFromMediaId(downloaded.mediaId, Bundle()) }
        controller.waitUntilPlaying()
        assertFalse("Downloaded media must not stream", played("book-0", start))
        main { controller.transportControls.pause() }
    }

    @Test
    fun aSpokenTitlePlays() {
        signIn()
        val controller = connect().controller()
        main { controller.transportControls.playFromSearch("Stories for Tomorrow 02", Bundle()) }
        controller.waitUntilPlaying()
        assertTrue(played("book-1"))
        main { controller.transportControls.pause() }
    }

    @Test
    fun otherAppsCannotBrowseTheLibrary() {
        signIn()
        instrumentation.context.startActivity(Intent().setClassName("com.audiobookshelf.app.nativepreview.test", ForeignBrowserActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val shown = Device.device.wait(Until.findObject(By.textStartsWith("browse ")), 20_000) ?: throw AssertionError("The other app never finished connecting")
        assertEquals("browse refused", shown.text)
        Device.device.pressBack()
    }
}
