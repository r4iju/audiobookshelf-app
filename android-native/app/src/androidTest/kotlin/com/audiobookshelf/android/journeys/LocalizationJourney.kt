package com.audiobookshelf.android.journeys

import android.app.LocaleManager
import android.os.LocaleList
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The main screens in the person's chosen app language, using the translations the legacy app ships. */
@RunWith(AndroidJUnit4::class)
class LocalizationJourney {
    @get:Rule val compose = createEmptyComposeRule()

    private val locales get() = InstrumentationRegistry.getInstrumentation().targetContext.getSystemService(LocaleManager::class.java)

    @After fun restore() { locales.applicationLocales = LocaleList.getEmptyLocaleList() }

    @Test
    fun theMainScreensFollowTheAppLanguage() {
        Fixture.resetAppData()
        Fixture.configure("pdf-reader")
        InstrumentationRegistry.getInstrumentation().runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags("de") }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForText("Verbinden")
            compose.signIn()
            compose.waitForText("Bibliothek")
            compose.waitForText("Weiterhören")
            compose.tap("item-book-0")
            compose.waitForText("Abspielen")
            compose.waitForText("Herunterladen")
            compose.tap("back")
            compose.waitForText("Suchen")
            compose.tap("open-settings")
            compose.waitForText("Einstellungen")
            compose.capture("localized-settings")
        }
    }

    @Test
    fun connectionAndSignInErrorsFollowTheAppLanguage() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        InstrumentationRegistry.getInstrumentation().runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags("de") }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitForTag("server-address")
            compose.replaceText("server-address", "books.example.com")
            compose.tap("connect")
            compose.waitForText("Gib eine Serveradresse ein, die mit http:// oder https:// beginnt, zum Beispiel https://books.example.com/abs.")
            compose.replaceText("server-address", Fixture.server)
            compose.tap("connect")
            compose.waitForTag("username")
            compose.replaceText("username", "qa")
            compose.replaceText("password", "not-the-password")
            compose.tap("sign-in")
            compose.waitForText("Benutzername oder Passwort wurden nicht akzeptiert.")
            compose.capture("localized-sign-in-error")
        }
    }

    @Test
    fun libraryControlsReadRightToLeftInArabic() {
        Fixture.resetAppData()
        Fixture.configure("baseline")
        InstrumentationRegistry.getInstrumentation().runOnMainSync { locales.applicationLocales = LocaleList.forLanguageTags("ar") }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.signIn()
            val width = compose.onRoot().fetchSemanticsNode().size.width
            assertTrue("Settings sits at the start of a right-to-left top bar", compose.onNodeWithTag("open-settings").fetchSemanticsNode().boundsInRoot.center.x < width / 2)
            compose.tap("open-sort")
            compose.waitForText("أضيفت على")
            compose.capture("localized-sort-ar")
            compose.pressBack()
            compose.tap("open-filter")
            compose.waitForText("التصنيف")
        }
    }
}
