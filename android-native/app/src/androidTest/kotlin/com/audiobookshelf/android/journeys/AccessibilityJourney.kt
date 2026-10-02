package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Runs the Accessibility Test Framework's checks (labels, touch targets, contrast) on each main screen. */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class AccessibilityJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private fun check(capture: String) {
        compose.waitForIdle()
        compose.onRoot().tryPerformAccessibilityChecks()
        compose.capture("a11y-$capture")
    }

    @Test
    fun mainScreensPassAccessibilityChecks() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        ActivityScenario.launch(MainActivity::class.java).use {
            val validator = com.google.android.apps.common.testing.accessibility.framework.integrations.espresso.AccessibilityValidator()
                .setRunChecksFromRootView(true)
                .setThrowExceptionFor(com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResult.AccessibilityCheckResultType.ERROR)
            (compose as androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, *>).setComposeAccessibilityValidator(object : androidx.compose.ui.test.ComposeAccessibilityValidator { override fun check(view: android.view.View) { validator.check(view) } })
            compose.waitForTag("server-address")
            check("connect")
            compose.signIn()
            check("library")
            compose.tap("item-book-0")
            compose.waitForTag("read-ebook")
            check("item")
            compose.tap("play")
            compose.waitForTag("player-screen", 20_000)
            check("player")
            compose.tap("play-pause")
            compose.tap("player-collapse")
            compose.tap("back")
            compose.tap("tab-downloads")
            check("downloads")
            compose.tap("tab-search")
            check("search")
            compose.tap("tab-library")
            compose.tap("open-settings")
            check("settings")
        }
    }
}
