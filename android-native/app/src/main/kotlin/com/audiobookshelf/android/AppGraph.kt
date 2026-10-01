package com.audiobookshelf.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.CredentialVault
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.core.DeviceInfo
import com.audiobookshelf.core.ListeningJournal
import com.audiobookshelf.android.playback.PlaybackEngine
import com.audiobookshelf.android.playback.ProgressSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import com.audiobookshelf.core.ApiClient
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Process-wide dependencies, created lazily so tests can reset app data before first use. */
class AppGraph private constructor(val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    val deviceInfo: DeviceInfo by lazy {
        val file = File(context.filesDir, "device-id")
        val id = file.takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
            ?: UUID.randomUUID().toString().also { file.parentFile?.mkdirs(); file.writeText(it) }
        DeviceInfo(id, "Audiobookshelf Android", BuildConfig.VERSION_NAME, Build.MANUFACTURER, Build.MODEL, Build.VERSION.SDK_INT)
    }
    val settings by lazy { SettingsStore(File(context.filesDir, "settings.json")) }
    val diagnostics by lazy { com.audiobookshelf.android.data.Diagnostics(File(context.filesDir, "diagnostics.json")) }
    /** Requests from the media notification to show the full player. */
    val openPlayerRequests = kotlinx.coroutines.flow.MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    /** Serializes journal file writes off the main thread, preserving their order. */
    val io = kotlinx.coroutines.Dispatchers.IO.limitedParallelism(1)
    val journal: ListeningJournal by lazy { openJournal(File(context.filesDir, "listening-journal.json")) }
    val progressSync by lazy {
        ProgressSync(scope, journal, accounts, io, diagnostics::record).also { sync ->
            context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = sync.publishAll()
            })
        }
    }
    /** Creating the engine closes listening left open by a previous process and publishes it. */
    val playback: PlaybackEngine by lazy {
        journal.finishRecoveredSessions()
        PlaybackEngine(context, scope, http, settings, accounts, journal, progressSync, { deviceInfo }, io, diagnostics::record,
            resetPending = { account, itemId, episodeId ->
                when {
                    resets.unreadable.value -> "Saved progress discards could not be read, so nothing plays until they are resolved in Diagnostics."
                    resets.pending(account, itemId, episodeId) -> "Progress for this title is still being discarded. It plays from the beginning once that is done."
                    else -> null
                }
            }).also { progressSync.publishAll() }
    }

    val downloads by lazy {
        com.audiobookshelf.android.download.Downloads(context, com.audiobookshelf.android.download.DownloadStore(File(context.filesDir, "downloads.json")), accounts, settings, journal, http, diagnostics::record)
    }

    val reading by lazy { com.audiobookshelf.android.reader.ReadingStore(File(context.filesDir, "reading-positions.json")) }
    val readingSync by lazy {
        com.audiobookshelf.android.reader.ReadingSync(scope, reading, remoteFor = { account ->
            accounts.clientFor(account)?.let { client ->
                object : com.audiobookshelf.android.reader.ReadingRemote {
                    override suspend fun progress(itemId: String) = client.progress(itemId, null)
                    override suspend fun save(itemId: String, location: String, progress: Double) = client.saveEbookProgress(itemId, location, progress)
                }
            }
        }, onSignInRequired = accounts::handle, report = diagnostics::record,
            listeningGate = { account, publication -> playback.publishReading(account, publication) },
            held = { account, itemId -> resets.pending(account, itemId, null) }).also { sync ->
            context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = sync.publishAll()
            })
            scope.launch { playback.listeningEnded.collect { sync.publishAll() } }
            sync.publishAll()
        }
    }

    val resets: com.audiobookshelf.core.ProgressResets by lazy {
        com.audiobookshelf.core.ProgressResets(File(context.filesDir, "progress-resets.json"), remoteFor = { account ->
            accounts.clientFor(account)?.let { client ->
                object : com.audiobookshelf.core.ProgressRemote {
                    override suspend fun progress(itemId: String, episodeId: String?) = client.progress(itemId, episodeId)
                    override suspend fun remove(progressId: String) = client.removeProgress(progressId)
                }
            }
        }, exclusive = { reset, block -> playback.excludingTitle(reset.account, reset.itemId, reset.episodeId, block) },
            cleanup = { reset, at ->
                journal.resetPosition(reset.account, reset.itemId, reset.episodeId, at)
                if (reset.episodeId == null) reading.forget(reset.account, reset.itemId)
            })
    }

    private var resetRetry: kotlinx.coroutines.Job? = null
    private var resetBackoffMs = 1_000L

    private var resetsStarted = false

    /** Completes discarded progress left from before, and again whenever a network or the account returns. */
    fun startResets() {
        if (resetsStarted) return
        resetsStarted = true
        context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { scope.launch { completeResets() } }
        })
        scope.launch {
            accounts.session.map { (it as? com.audiobookshelf.android.data.SessionState.Active)?.client?.account }.distinctUntilChanged().collect { completeResets() }
        }
    }

    /** Resumes discarded progress that is not yet complete, for every signed-in account that asked for it. */
    fun completeResets() {
        scope.launch {
            var failed = false
            for (account in resets.pendingAccounts()) {
                if (accounts.clientFor(account) == null) continue
                val done = try {
                    kotlinx.coroutines.withContext(Dispatchers.IO) { resets.complete(account) }
                } catch (failure: Exception) {
                    accounts.handle(failure)
                    diagnostics.record(com.audiobookshelf.android.data.Diagnostics.Area.SYNC, "Discarding progress did not finish yet; it is retried", failure)
                    false
                }
                failed = failed || !done
            }
            // Pages held for completed resets, and for other titles, can go now.
            readingSync.publishAll()
            if (!failed) { resetBackoffMs = 1_000L; return@launch }
            if (resetRetry?.isActive == true) return@launch
            val wait = resetBackoffMs
            resetBackoffMs = (resetBackoffMs * 2).coerceAtMost(60_000L)
            resetRetry = scope.launch { kotlinx.coroutines.delay(wait); resetRetry = null; completeResets() }
        }
    }

    /**
     * Discards a title's progress on the server and on this device, as the existing app does. The
     * request is saved first and completed in the background when it cannot finish now; the title's
     * listening is sent before anything is deleted, so none of it can recreate the progress afterwards.
     */
    suspend fun discardProgress(client: ApiClient, itemId: String, episodeId: String?): Boolean {
        val account = client.account
        kotlinx.coroutines.withContext(io) { resets.request(account, itemId, episodeId) }
        val done = try {
            kotlinx.coroutines.withContext(Dispatchers.IO) { resets.complete(account) }
        } catch (failure: Exception) {
            accounts.handle(failure)
            false
        }
        if (done) readingSync.publishAll() else completeResets()
        return done
    }

    val podcastRequests by lazy { com.audiobookshelf.android.podcast.PodcastRequests(File(context.filesDir, "podcast-requests.json")) }
    val serverEvents by lazy {
        com.audiobookshelf.android.podcast.ServerEvents(scope, accounts, http).also { events ->
            events.start()
            scope.launch {
                events.events.collect { event ->
                    val data = event.data ?: return@collect
                    if (event.name == "episode_download_finished" && data.optBoolean("failed")) {
                        val itemId = data.optString("libraryItemId"); val url = data.optString("url")
                        if (itemId.isNotEmpty() && url.isNotEmpty()) runCatching { podcastRequests.receiveFailure(event.account, itemId, url, data.optString("id")) }
                    }
                }
            }
        }
    }

    val accounts by lazy { AccountStore(CredentialVault(File(context.noBackupFilesDir, "vault/connections.bin")), http, deviceInfo).also { it.restore() } }

    private fun openJournal(file: File): ListeningJournal = try {
        ListeningJournal(file)
    } catch (error: ListeningJournal.Unreadable) {
        // Keep the unreadable document for recovery instead of overwriting it.
        file.renameTo(File(file.parentFile, "${file.name}.unreadable-${System.currentTimeMillis()}"))
        ListeningJournal(file)
    }

    companion object {
        @Volatile private var instance: AppGraph? = null
        fun get(context: Context): AppGraph = instance ?: synchronized(this) {
            instance ?: AppGraph(context.applicationContext).also { instance = it }
        }
    }
}

val Context.graph: AppGraph get() = AppGraph.get(this)
