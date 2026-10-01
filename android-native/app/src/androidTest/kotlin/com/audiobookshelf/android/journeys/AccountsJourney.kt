package com.audiobookshelf.android.journeys

import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.audiobookshelf.android.MainActivity
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AccountsJourney {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun a_openIdThroughBrowserThenSecondAccountOnAnotherServerAndSwitchBack() {
        Fixture.resetAppData()
        Fixture.configure("openid")
        Fixture.configure("baseline", Fixture.secondServer)
        launchThroughBrowser {
            compose.waitForTag("server-address")
            compose.replaceText("server-address", Fixture.server)
            compose.tap("connect")
            compose.tap("openid-sign-in")
            Browser.approve()
            compose.waitForTag("library-home", 30_000)
            compose.waitForText("Stories for Tomorrow 01")
            assertTrue(Fixture.requests().any { it.getString("path") == "/auth/openid/callback" })

            compose.tap("open-accounts")
            compose.tap("add-account")
            compose.signIn(Fixture.secondServer, "qa-other")
            compose.tap("open-accounts")
            compose.waitForTag("account-qa")
            compose.onNodeWithTag("active-account").assertTextContains("qa-other", substring = true)
            compose.tap("account-qa")
            compose.waitForTag("library-home", 20_000)
            compose.tap("open-accounts")
            compose.onNodeWithTag("active-account").assertTextContains("qa", substring = true)
        }
        assertTrue("Second account used its own server", Fixture.requests(Fixture.secondServer).any { it.getString("path") == "/login" })
    }

    @Test
    fun b_relaunchRestoresTheLastActiveAccountWithBothSaved() {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("library-home", 20_000)
            compose.tap("open-accounts")
            compose.onNodeWithTag("active-account").assertTextContains(Fixture.server.removePrefix("http://"), substring = true)
            compose.waitForTag("account-qa-other")
        }
    }

    @Test
    fun c_rejectedOrCanceledBrowserSignInKeepsSavedAccounts() {
        Fixture.configure("openid-invalid-state")
        launchThroughBrowser {
            compose.waitForTag("library-home", 20_000)
            compose.tap("open-accounts")
            compose.tap("add-account")
            compose.replaceText("server-address", Fixture.server)
            compose.tap("connect")
            compose.tap("openid-sign-in")
            Browser.approve()
            compose.waitForTag("openid-error", 30_000)
            compose.onNodeWithTag("openid-error").assertTextContains("could not be verified", substring = true)

            Fixture.configure("openid")
            compose.tap("openid-sign-in")
            Browser.waitForProvider()
            Browser.back()
            compose.waitForText("canceled", 20_000)
            compose.tap("cancel-add-account")
            compose.waitForTag("active-account", 20_000)
            compose.waitForTag("account-qa-other")
            assertFalse(compose.isShown("server-address"))
        }
    }

    /**
     * The browser callback re-enters the singleTask activity through a new intent, after which
     * ActivityScenario no longer tracks it and fails on close; the orchestrator ends the process
     * after each method, so the scenario is left open.
     */
    private fun launchThroughBrowser(body: () -> Unit) {
        ActivityScenario.launch(MainActivity::class.java)
        body()
    }
}
