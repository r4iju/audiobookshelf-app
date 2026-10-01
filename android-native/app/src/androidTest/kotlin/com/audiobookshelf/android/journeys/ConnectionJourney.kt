package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.assertTextContains
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File

/**
 * Methods run in name order under the orchestrator, each in a fresh app process, so a later
 * method observes real process death and relaunch of what an earlier method persisted.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class ConnectionJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun a_invalidAndUntrustedAddressesExplainRecoveryThenPasswordSignInReachesLibrary() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("server-address")
            compose.replaceText("server-address", "books.lan")
            compose.tap("connect")
            compose.waitForTag("connection-error")
            compose.onNodeWithTag("connection-error").assertTextContains("http://", substring = true)

            compose.replaceText("server-address", Fixture.untrustedServer)
            compose.tap("connect")
            compose.waitForText("not trusted", 20_000)

            compose.replaceText("server-address", Fixture.server)
            compose.tap("connect")
            compose.waitForTag("username")
            compose.replaceText("username", "qa")
            compose.replaceText("password", "wrong")
            compose.tap("sign-in")
            compose.waitForTag("sign-in-error")
            compose.onNodeWithTag("sign-in-error").assertTextContains("not accepted", substring = true)

            compose.replaceText("password", "qa")
            compose.tap("sign-in")
            compose.waitForTag("library-home", 20_000)
            compose.waitForText("Stories for Tomorrow 01")
            compose.tap("library-picker")
            compose.tap("library-option-podcasts")
            compose.waitForText("Evening Stories")
        }
        val requests = Fixture.requests()
        assertTrue("Refreshed bearer reached the subpath API", requests.any { it.getString("path") == "/auth/refresh" })
        assertTrue(requests.any { it.getString("path") == "/api/libraries/podcasts/items" })
    }

    @Test
    fun b_relaunchRestoresAccountAndLibraryWithoutPlaintextSecrets() {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.waitForText("Evening Stories")
            assertFalse(compose.isShown("server-address"))
        }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val stored = File(context.applicationInfo.dataDir).walkTopDown().filter { it.isFile }.map { it.readBytes().decodeToString() }.toList()
        // Fixture token values are exactly fresh/refresh/expired (optionally -other); header names like x-refresh-token are not secrets.
        val token = Regex("(?<![\\w-])(fresh|refresh|expired)(-other)?(?![\\w-])")
        assertFalse("Tokens are never stored in plaintext", stored.any { token.containsMatchIn(it) })
    }

    @Test
    fun c_temporaryServerFailureKeepsAccountAndRecoversInPlace() {
        Fixture.configure("offline-library")
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("catalog-error", 20_000)
            assertFalse(compose.isShown("server-address"))
            assertFalse(compose.isShown("username"))
            Fixture.configure("baseline")
            compose.tap("catalog-retry")
            compose.waitForText("Evening Stories", 20_000)
        }
    }
}
