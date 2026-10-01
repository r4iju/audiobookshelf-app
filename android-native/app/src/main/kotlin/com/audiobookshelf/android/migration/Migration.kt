package com.audiobookshelf.android.migration

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.Appearance
import com.audiobookshelf.android.data.DeviceSettings
import com.audiobookshelf.android.data.Diagnostics
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.android.download.Downloads
import com.audiobookshelf.android.reader.ReadingStore
import com.audiobookshelf.android.ui.PRIMARY_EBOOK
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.ListeningJournal
import com.audiobookshelf.core.ListeningMedia
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.migration.Attachment
import com.audiobookshelf.core.migration.Issue
import com.audiobookshelf.core.migration.LegacyArchive
import com.audiobookshelf.core.migration.LegacyImport
import com.audiobookshelf.core.migration.MigrationError
import com.audiobookshelf.core.migration.Outcome
import com.audiobookshelf.core.migration.Plan
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.floatOrNull
import java.io.File

/**
 * Imports an export of the previous Android app, chosen by the user. The previous app and the export
 * are only read. Titles, listening and positions attach to an account only once that same account
 * has signed in here; until then they wait in this app's storage.
 */
class Migration(
    private val context: Context,
    private val scope: CoroutineScope,
    private val accounts: AccountStore,
    private val settings: SettingsStore,
    private val downloads: Downloads,
    private val journal: () -> ListeningJournal,
    private val reading: ReadingStore,
    private val deviceId: () -> String,
    private val published: () -> Unit,
    private val report: com.audiobookshelf.android.data.Report,
) {
    sealed interface Step {
        data object Reading : Step
        data class Refused(val message: String) : Step
        data class Ready(val name: String, val plan: Plan) : Step
        data class Importing(val copied: Int, val total: Int) : Step
        data class Done(val outcome: Outcome, val waiting: List<com.audiobookshelf.core.migration.ImportedAccount>) : Step
        data class Already(val outcome: Outcome) : Step
    }

    private val import = LegacyImport(File(context.filesDir, "migration"))
    private val incoming get() = File(context.cacheDir, "migration-incoming/export.absmigration")
    private val lock = Mutex()
    private var archive: LegacyArchive? = null

    private val state = MutableStateFlow<Step?>(null)
    /** What the import screen shows; null when it is closed. */
    val step: StateFlow<Step?> = state

    val interrupted get() = import.interrupted

    fun open(uri: Uri) {
        state.value = Step.Reading
        scope.launch {
            state.value = try {
                withContext(Dispatchers.IO) { read(uri) }
            } catch (refused: MigrationError) {
                incoming.delete()
                Step.Refused(when (refused) {
                    is MigrationError.Unreadable, is MigrationError.Incomplete -> "This file is not a complete export from the Audiobookshelf app. Export again from the previous app and choose the new file."
                    is MigrationError.Unsupported -> "This export was made by a newer version of the previous app. Update this app, then try again."
                    is MigrationError.FromAnotherPlatform -> "This export was made on another kind of device. Choose an export from the Android app."
                    is MigrationError.AnotherArchiveImported -> "Another export was already imported here. Clear this app's data first to import a different one."
                    is MigrationError.InsufficientSpace -> refused.message.orEmpty()
                })
            } catch (failure: Exception) {
                incoming.delete()
                report(Diagnostics.Area.STORAGE, "The chosen export could not be read", failure)
                Step.Refused("The chosen file could not be read. Choose it again, or save it to this device first.")
            }
        }
    }

    private fun read(uri: Uri): Step {
        incoming.parentFile?.mkdirs()
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment.orEmpty()
        (resolver.openInputStream(uri) ?: throw MigrationError.Unreadable()).use { input -> incoming.outputStream().use { input.copyTo(it) } }
        val opened = LegacyArchive.open(incoming)
        import.outcome()?.let { committed ->
            incoming.delete()
            if (committed.fingerprint == opened.fingerprint) return Step.Already(committed)
            throw MigrationError.AnotherArchiveImported()
        }
        archive = opened
        val plan = import.preflight(opened, emptySet(), context.filesDir.usableSpace)
        return Step.Ready(name, plan.copy(accounts = plan.accounts.map { it.copy(signedIn = accounts.clientFor(it.identity) != null) }))
    }

    fun start() {
        val chosen = archive ?: return
        scope.launch {
            val total = chosen.manifest.storedPaths.size
            var copied = 0
            state.value = Step.Importing(0, total)
            try {
                val outcome = withContext(Dispatchers.IO) {
                    import.run(chosen) { copied++; state.value = Step.Importing(copied, total) }.let(::applySettings)
                }
                incoming.delete()
                archive = null
                state.value = Step.Done(outcome, outcome.accounts.filter { accounts.clientFor(it.identity) == null })
                attachSignedIn()
            } catch (failure: Exception) {
                report(Diagnostics.Area.STORAGE, "The import stopped", failure)
                state.value = Step.Refused(when (failure) {
                    is MigrationError -> failure.message.orEmpty()
                    else -> "The import stopped before it finished. Nothing was lost: choose the same export again to continue where it stopped."
                })
            }
        }
    }

    fun close() {
        state.value = null
        archive = null
        incoming.delete()
    }

    /** Attaches waiting titles and listening to every account signed in on this device. */
    fun attachSignedIn() {
        val outcome = import.outcome() ?: return
        outcome.accounts.mapNotNull { accounts.clientFor(it.identity) }.forEach { client -> scope.launch { attach(client) } }
    }

    private suspend fun attach(client: ApiClient) = lock.withLock {
        try {
            withContext(Dispatchers.IO) { attachNow(client) }
        } catch (failure: Exception) {
            accounts.handle(failure)
            report(Diagnostics.Area.STORAGE, "Imported titles for ${client.account.server} are not attached yet; they are tried again", failure)
        }
    }

    private suspend fun attachNow(client: ApiClient) {
        val outcome = import.outcome() ?: return
        val account = client.account
        val issues = mutableListOf<Issue>()
        val titles = outcome.titles.map { title ->
            if (title.account != account || title.attached) return@map title
            val item = try {
                client.item(title.itemId)
            } catch (gone: ApiError.Http) {
                if (gone.status != 404) throw gone
                issues += Issue(Issue.Kind.ITEM_CHANGED, title.title, "It is no longer on the server, so it was not adopted.")
                return@map title.copy(attached = true)
            }
            val match = Attachment.match(title, item, title.episodeId)
            if (match.problem != null) {
                issues += Issue(Issue.Kind.ITEM_CHANGED, title.title, match.problem!!)
                return@map title.copy(attached = true)
            }
            val episode = title.episodeId?.let { id -> item.media.episodes.firstOrNull { it.id == id } }
            downloads.adopt(account, item, episode, match.audio.map { it?.let(import::staged) }, match.ebook?.let(import::staged))
            title.copy(attached = true)
        }
        val sessions = outcome.sessions.map { imported ->
            val session = imported.session
            val itemId = session.libraryItemId
            if (imported.account != account || imported.attached || itemId == null) return@map imported
            if (session.duration > 0) journal().adopt(
                session.id, account,
                ListeningMedia(itemId, session.episodeId, session.displayTitle.orEmpty(), session.displayAuthor.orEmpty(), session.mediaType, session.duration, session.startTime, session.playMethod),
                deviceId(), session.startedAt.toDouble(), session.updatedAt.toDouble(), session.currentTime, session.timeListening,
            )
            imported.copy(attached = true)
        }
        val progress = outcome.progress.map { imported ->
            val entry = imported.progress
            val itemId = entry.libraryItemId
            if (imported.account != account || imported.attached || itemId == null) return@map imported
            val updated = entry.lastUpdate.toDouble()
            if (entry.currentTime > 0) journal().adoptRemotePosition(account, itemId, entry.episodeId, entry.currentTime, updated)
            // Other formats' locations stay in the import until their readers exist.
            if (entry.episodeId == null && entry.ebookLocation != null) {
                reading.adoptRemote(account, itemId, PRIMARY_EBOOK, MediaProgress(libraryItemId = itemId, ebookLocation = entry.ebookLocation, lastUpdate = updated))
            }
            imported.copy(attached = true)
        }
        import.save(outcome.copy(titles = titles, sessions = sessions, progress = progress, issues = outcome.issues + issues))
        import.releaseAttached()
        published()
    }

    /** The previous app's device settings and display preferences, applied once. */
    private fun applySettings(outcome: Outcome): Outcome {
        if (outcome.settingsApplied) return outcome
        settings.update { current -> legacySettings(current, outcome) }
        return outcome.copy(settingsApplied = true).also(import::save)
    }

    private fun legacySettings(current: DeviceSettings, outcome: Outcome): DeviceSettings {
        val serializer = DeviceSettings.serializer()
        val known = (0 until serializer.descriptor.elementsCount).map(serializer.descriptor::getElementName).toSet()
        var merged = current
        // Each field on its own, so one value this app cannot use leaves the others applied.
        outcome.deviceSettings?.filterKeys { it in known }?.forEach { (key, value) ->
            val candidate = JsonObject(AbsJson.encodeToJsonElement(serializer, merged).jsonObject + (key to value))
            runCatching { AbsJson.decodeFromJsonElement(serializer, candidate) }.onSuccess { merged = it }
        }
        val preferences = outcome.preferences
        preferences["userSettings"]?.let { text ->
            runCatching { AbsJson.parseToJsonElement(text).jsonObject["playbackRate"]?.jsonPrimitive?.floatOrNull }.getOrNull()
                ?.takeIf { it in 0.5f..3f }?.let { merged = merged.copy(playbackRate = it) }
        }
        preferences["bookshelfListView"]?.let { merged = merged.copy(listLayout = it == "1") }
        preferences["theme"]?.let { theme -> Appearance.entries.firstOrNull { it.name.equals(theme, ignoreCase = true) }?.let { merged = merged.copy(appearance = it) } }
        return merged
    }
}
