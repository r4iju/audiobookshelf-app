package com.audiobookshelf.android.journeys

import android.app.LocaleManager
import android.os.LocaleList
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.audiobookshelf.android.MainActivity
import org.junit.After
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
}
