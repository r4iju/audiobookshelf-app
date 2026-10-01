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
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
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
    /** Requests from the media notification to show the full player. */
    val openPlayerRequests = kotlinx.coroutines.flow.MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    /** Serializes journal file writes off the main thread, preserving their order. */
    val io = kotlinx.coroutines.Dispatchers.IO.limitedParallelism(1)
    val journal: ListeningJournal by lazy { openJournal(File(context.filesDir, "listening-journal.json")) }
    val progressSync by lazy {
        ProgressSync(scope, journal, accounts, io).also { sync ->
            context.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = sync.publishAll()
            })
        }
    }
    /** Creating the engine closes listening left open by a previous process and publishes it. */
    val playback by lazy {
        journal.finishRecoveredSessions()
        PlaybackEngine(context, scope, http, settings, accounts, journal, progressSync, { deviceInfo }, io).also { progressSync.publishAll() }
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
