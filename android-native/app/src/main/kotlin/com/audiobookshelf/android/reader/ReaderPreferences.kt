package com.audiobookshelf.android.reader

import android.content.Context
import org.json.JSONObject

/** Retains all legacy keys, including fields the current presentation cannot apply. */
class ReaderPreferences(context: Context) {
    private val preferences = context.getSharedPreferences("publication-reader", 0)
    private var writable = true
    fun current(): JSONObject = runCatching { JSONObject(preferences.getString("settings", "{}")!!) }.getOrElse { writable = false; JSONObject() }
    fun update(settings: JSONObject) { check(writable) { "Unreadable reading settings are preserved" }; check(preferences.edit().putString("settings", settings.toString()).commit()) { "Reading settings could not be saved" } }
    fun adoptLegacy(serialized: String?) {
        if (serialized == null || preferences.contains("settings") || preferences.getBoolean("legacy-applied", false)) return
        val legacy = runCatching { JSONObject(serialized) }.getOrNull() ?: return
        check(preferences.edit().putString("settings", legacy.toString()).putBoolean("legacy-applied", true).commit()) { "Reading settings could not be imported" }
    }
}
