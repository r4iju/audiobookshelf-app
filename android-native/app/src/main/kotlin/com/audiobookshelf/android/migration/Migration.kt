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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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
import java.util.UUID

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
    /** One chosen file, copied to its own place so a later choice never shares it. */
    private class Selection(val file: File) { var archive: LegacyArchive? = null }

    private val incoming = File(context.cacheDir, "migration-incoming").apply { deleteRecursively() }
    private val lock = Mutex()
    // Confined to the main thread, where every choice, close and import starts.
    private var selection: Selection? = null
    private var reader: Job? = null
    private var importing = false

    private val state = MutableStateFlow<Step?>(null)
    /** What the import screen shows; null when it is closed. */
    val step: StateFlow<Step?> = state

    val interrupted get() = import.interrupted

    /** Reads a chosen export, replacing any choice still being read. A choice made while an import runs is ignored. */
    fun open(uri: Uri) {
        if (importing) return
        release()
        val mine = Selection(File(incoming, "${UUID.randomUUID()}.absmigration"))
        selection = mine
        state.value = Step.Reading
        reader = scope.launch {
            val result = try {
                withContext(Dispatchers.IO) { read(uri, mine) }
            } catch (refused: MigrationError) {
                Step.Refused(refused.message.orEmpty())
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                report(Diagnostics.Area.STORAGE, "The chosen export could not be read", failure)
                Step.Refused("The chosen file could not be read. Choose it again, or save it to this device first.")
            } finally {
                // Runs once the copy has stopped, so nothing writes the file after it is removed.
                if (selection !== mine || mine.archive == null) mine.file.delete()
            }
            if (selection === mine) state.value = result
        }
    }

    private suspend fun read(uri: Uri, mine: Selection): Step {
        incoming.mkdirs()
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment.orEmpty()
        (resolver.openInputStream(uri) ?: throw MigrationError.Unreadable()).use { input ->
            mine.file.outputStream().use { output ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                }
            }
        }
        val opened = LegacyArchive.open(mine.file)
        import.outcome()?.let { committed ->
            if (committed.fingerprint == opened.fingerprint) return Step.Already(committed)
            throw MigrationError.AnotherArchiveImported()
        }
        val plan = import.preflight(opened, emptySet(), context.filesDir.usableSpace)
        currentCoroutineContext().ensureActive()
        mine.archive = opened
        return Step.Ready(name, plan.copy(accounts = plan.accounts.map { it.copy(signedIn = accounts.clientFor(it.identity) != null) }))
    }

    fun start() {
        val mine = selection ?: return
        val chosen = mine.archive ?: return
        if (importing) return
        importing = true
        scope.launch {
            val total = chosen.manifest.storedPaths.size
            var copied = 0
            state.value = Step.Importing(0, total)
            try {
                val outcome = withContext(Dispatchers.IO) {
                    import.run(chosen) { copied++; state.value = Step.Importing(copied, total) }.let(::applySettings)
                }
                state.value = Step.Done(outcome, outcome.accounts.filter { accounts.clientFor(it.identity) == null })
                attachSignedIn()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                report(Diagnostics.Area.STORAGE, "The import stopped", failure)
                state.value = Step.Refused(when (failure) {
                    is MigrationError -> failure.message.orEmpty()
                    else -> "The import stopped before it finished. Nothing was lost: choose the same export again to continue where it stopped."
                })
            } finally {
                importing = false
                if (selection === mine) selection = null
                withContext(NonCancellable + Dispatchers.IO) { mine.file.delete() }
            }
        }
    }

    /** Closes the import screen; an import already running continues and reports when it is done. */
    fun close() {
        if (importing) return
        release()
        state.value = null
    }

    /** Gives up the current choice: a read in progress stops and removes its own file; a finished one is removed here. */
    private fun release() {
        val previous = selection ?: return
        selection = null
        val running = reader
        if (running?.isActive == true) running.cancel() else previous.file.delete()
    }

    /** Attaches waiting titles and listening to every account signed in on this device. */
    fun attachSignedIn() {
        val outcome = import.outcome() ?: return
        outcome.accounts.mapNotNull { accounts.clientFor(it.identity) }.forEach { client -> scope.launch { attach(client) } }
    }

    private suspend fun attach(client: ApiClient) = lock.withLock {
        try {
            withContext(Dispatchers.IO) { attachNow(client) }
        } catch (cancelled: CancellationException) {
            throw cancelled
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
            val chosen = match.audio.filterNotNull() + listOfNotNull(match.ebook)
            if (chosen.any { import.verified(it) == null }) {
                issues += Issue(Issue.Kind.FILE_CORRUPT, title.title, "A file changed on this device after it was imported, so this title is not adopted. Download it again.")
                return@map title.copy(attached = true)
            }
            val episode = title.episodeId?.let { id -> item.media.episodes.firstOrNull { it.id == id } }
            val cover = runCatching { client.bytes("api/items/${item.id}/cover") }.getOrNull()
            downloads.adopt(account, item, episode, match.tracks, match.audio.map { it?.let(import::verified) }, match.ebook?.let(import::verified), cover)
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
            // Only a page number is a PDF position; other formats' locations stay in the import until their readers exist.
            if (entry.episodeId == null && entry.ebookLocation?.toIntOrNull()?.let { it > 0 } == true) {
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
