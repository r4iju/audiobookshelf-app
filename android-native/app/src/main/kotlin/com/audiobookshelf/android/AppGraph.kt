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
class AppGraph internal constructor(val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    val deviceInfo: DeviceInfo by lazy {
        val file = File(context.filesDir, "device-id")
        val id = file.takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
            ?: UUID.randomUUID().toString().also { file.parentFile?.mkdirs(); file.writeText(it) }
        DeviceInfo(id, "${context.getString(R.string.product_name)} Android", BuildConfig.VERSION_NAME, Build.MANUFACTURER, Build.MODEL, Build.VERSION.SDK_INT)
    }
    val settings by lazy { SettingsStore(File(context.filesDir, "settings.json")) }
    val diagnostics by lazy { com.audiobookshelf.android.data.Diagnostics(File(context.filesDir, "diagnostics.json")) }
    /** Requests from the media notification to show the full player. */
    val openPlayerRequests = kotlinx.coroutines.flow.MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    /** Serializes journal file writes off the main thread, preserving their order. */
    val io = kotlinx.coroutines.Dispatchers.IO.limitedParallelism(1)
    /** Progress writes that may still be applied by the server; see [com.audiobookshelf.core.PublicationLedger]. */
    val publications by lazy { com.audiobookshelf.core.PublicationLedger(File(context.filesDir, "publication-ledger.json")) }
    val journal: ListeningJournal by lazy { openJournal(File(context.filesDir, "listening-journal.json")) }
    /** Listening left by the previous process; nothing plays or publishes until it is saved. */
    val listeningRecovery by lazy {
        com.audiobookshelf.core.ListeningRecovery(journal, publications).also { recovery ->
            if (!recovery.run()) diagnostics.record(com.audiobookshelf.android.data.Diagnostics.Area.SYNC, "Listening from before the app closed could not be saved", recovery.problem.value)
        }
    }
    val progressSync by lazy {
        ProgressSync(scope, journal, accounts, io, publications, diagnostics::record, recovered = { listeningRecovery.run() }).also { sync ->
            context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = sync.publishAll()
            })
        }
    }
    /** Created on the main thread, which media routing requires. */
    val casting by lazy { com.audiobookshelf.android.playback.CastRoutes(context) }
    /** Creating the engine publishes listening left by a previous process once [listeningRecovery] is saved. */
    val playback: PlaybackEngine by lazy {
        listeningRecovery
        PlaybackEngine(context, scope, http, settings, accounts, journal, progressSync, { deviceInfo }, io, diagnostics::record,
            resetPending = { account, itemId, episodeId ->
                when {
                    !listeningRecovery.run() -> context.getString(R.string.set_play_blocked_listening_storage)
                    resets.unreadable.value -> context.getString(R.string.set_play_blocked_unreadable_resets)
                    resets.pending(account, itemId, episodeId) -> context.getString(R.string.set_play_blocked_discarding)
                    else -> null
                }
            }, casting = casting).also { progressSync.publishAll() }
    }

    val downloads by lazy {
        com.audiobookshelf.android.download.Downloads(context, com.audiobookshelf.android.download.DownloadStore(File(context.filesDir, "downloads.json")), accounts, settings, journal,
            com.audiobookshelf.android.download.DownloadFolder(context), http, diagnostics::record)
    }

    val reading by lazy { com.audiobookshelf.android.reader.ReadingStore(File(context.filesDir, "reading-positions.json")) }
    val readingSync by lazy {
        com.audiobookshelf.android.reader.ReadingSync(scope, reading, remoteFor = { account ->
            accounts.clientFor(account)?.let { client ->
                object : com.audiobookshelf.android.reader.ReadingRemote {
                    override suspend fun progress(itemId: String) = client.progress(itemId, null)
                    override suspend fun save(itemId: String, location: String, progress: Double) =
                        publications.publish(account, com.audiobookshelf.core.PublicationLedger.Kind.READING, listOf(com.audiobookshelf.core.PublicationLedger.Title(itemId, null))) {
                            client.saveEbookProgress(itemId, location, progress)
                        }
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
        }, exclusive = { reset, block ->
            // An earlier write that may still land would bring the progress back after the delete.
            playback.excludingTitle(reset.account, reset.itemId, reset.episodeId, ready = { !publications.uncertain(reset.account, reset.itemId, reset.episodeId) }, block)
        },
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

    /** Marks a title finished or not; the write is recorded so a discard cannot be overtaken by it. */
    suspend fun setFinished(client: ApiClient, itemId: String, episodeId: String?, finished: Boolean) =
        publications.publish(client.account, com.audiobookshelf.core.PublicationLedger.Kind.FINISHED, listOf(com.audiobookshelf.core.PublicationLedger.Title(itemId, episodeId))) {
            client.setFinished(itemId, episodeId, finished)
        }

    /**
     * The user's choice to discard a title's progress although an earlier write for it went
     * unanswered and may still reach the server, or to keep the progress instead.
     */
    suspend fun resolveUncertainDiscard(client: ApiClient, itemId: String, episodeId: String?, discard: Boolean): Boolean {
        val account = client.account
        if (!discard) return kotlinx.coroutines.withContext(io) { resets.withdraw(account, itemId, episodeId) }
        kotlinx.coroutines.withContext(io) { publications.accept(account, itemId, episodeId, keep = journal::freeze) }
        completeResets()
        return true
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

    val migration by lazy {
        com.audiobookshelf.android.migration.Migration(context, scope, accounts, settings, downloads, { journal }, reading, { deviceInfo.deviceId },
            published = { progressSync.publishAll(); readingSync.publishAll() }, report = diagnostics::record).also { migration ->
            scope.launch {
                accounts.session.map { (it as? com.audiobookshelf.android.data.SessionState.Active)?.client?.account }.distinctUntilChanged().collect { migration.attachSignedIn() }
            }
        }
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

    val accounts by lazy { AccountStore(CredentialVault(File(context.noBackupFilesDir, "vault/connections.bin")), http, deviceInfo, context).also { it.restore() } }

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
