package com.audiobookshelf.android.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.CellularPolicy
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.Episode
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.ListeningJournal
import com.audiobookshelf.core.MediaProgress
import com.audiobookshelf.core.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * Downloads items to app storage so they play without the server. Files land under a per-record
 * directory; a part is only renamed into place after its type and size are verified.
 */
class Downloads(
    private val context: Context,
    private val store: DownloadStore,
    private val accounts: AccountStore,
    private val settings: SettingsStore,
    private val journal: ListeningJournal,
    http: OkHttpClient,
    private val report: com.audiobookshelf.android.data.Report = { _, _, _ -> },
) {
    sealed interface Request {
        data object Started : Request
        data object NotAllowed : Request
        data object NoAudio : Request
        data object NeedsCellularConsent : Request
        data class NoSpace(val needed: Long) : Request
        /** The download list could not be written, so nothing was started. */
        data object NotSaved : Request
    }

    /** Transfers stall-fail after a minute without data, like the existing app. */
    private val transfer = http.newBuilder().readTimeout(60, TimeUnit.SECONDS).build()
    private val slots = Semaphore(3)
    val records = store.records

    fun find(account: AccountIdentity, itemId: String, episodeId: String?) = store.get(recordId(account, itemId, episodeId))

    /** Starts or restarts a download. [allowMetered] records the user's answer to the cellular question. */
    fun request(client: ApiClient, item: LibraryItem, episode: Episode?, canDownload: Boolean, allowMetered: Boolean = false): Request {
        if (!canDownload) return Request.NotAllowed
        val tracks = if (episode != null) listOfNotNull(episode.audioTrack?.let { it.copy(duration = it.duration.takeIf { d -> d > 0 } ?: episode.playableDuration) })
            else item.media.tracks.sortedBy { it.index ?: 0 }
        val ebook = item.media.ebookFile.takeIf { episode == null }
        if (tracks.isEmpty() && ebook == null || tracks.any { it.contentUrl == null }) return Request.NoAudio
        val sizes = tracks.map { it.metadata?.size } + listOfNotNull(ebook?.metadata?.size)
        val needed = sizes.filterNotNull().sum()
        val free = StatFs(context.filesDir.path)
        val reserve = maxOf(MIN_FREE_BYTES, free.totalBytes / 20)
        if (free.availableBytes - needed < reserve) return Request.NoSpace(needed)
        if (!allowMetered && settings.current.downloadUsingCellular == CellularPolicy.ASK && metered()) return Request.NeedsCellularConsent

        val id = recordId(client.account, item.id, episode?.id)
        val directory = File(context.filesDir, "downloads/$id")
        val parts = tracks.mapIndexed { index, track ->
            val ext = track.metadata?.ext?.takeIf { it.isNotBlank() }?.let { if (it.startsWith(".")) it else ".$it" } ?: extension(track.mimeType)
            DownloadStore.Part(track.contentUrl!! + "/download", "track-${index + 1}$ext", track.metadata?.size, track.mimeType)
        } + listOfNotNull(ebook?.let {
            DownloadStore.Part("/api/items/${item.id}/file/${it.ino}/download", "ebook.${it.format ?: "bin"}", it.metadata?.size, null, ebookFileId = it.ino, ebookFormat = it.format)
        })
        val previous = store.get(id)
        try { store.put(DownloadStore.Record(
            id = id, account = client.account, itemId = item.id, episodeId = episode?.id,
            title = episode?.title?.takeIf { it.isNotBlank() } ?: item.title,
            author = if (episode != null) item.title else item.author.orEmpty(),
            mediaType = item.mediaType,
            duration = episode?.playableDuration ?: item.media.duration ?: tracks.sumOf { it.duration },
            chapters = episode?.chapters ?: item.media.chapters,
            tracks = tracks.mapIndexed { index, track -> track.copy(index = index, startOffset = tracks.take(index).sumOf { it.duration }) },
            parts = parts.map { part -> previous?.parts?.firstOrNull { it.path == part.path && it.done }?.let { part.copy(done = true) } ?: part },
            directory = directory.path,
            allowMetered = allowMetered || settings.current.downloadUsingCellular == CellularPolicy.ALWAYS,
        )) } catch (failure: IOException) {
            Log.w(TAG, "Download list not saved", failure)
            return Request.NotSaved
        }
        enqueue(id)
        return Request.Started
    }

    /** False when the download list could not be written. */
    fun retry(id: String): Boolean {
        try {
            store.update(id) { it.copy(state = DownloadStore.State.QUEUED, error = null) } ?: return true
        } catch (failure: IOException) {
            Log.w(TAG, "Download list not saved", failure); return false
        }
        enqueue(id)
        return true
    }

    /**
     * Removes the record and then its files, so a record never points at deleted files; listening history
     * in the journal is kept. False when the download list could not be written and nothing was removed.
     */
    fun delete(id: String): Boolean {
        WorkManager.getInstance(context).cancelUniqueWork(workName(id))
        val record = store.get(id) ?: return true
        try { store.remove(id) } catch (failure: IOException) {
            Log.w(TAG, "Download list not saved", failure); return false
        }
        File(record.directory).deleteRecursively()
        return true
    }

    /** Re-enqueues downloads interrupted by process death; queued work already known to WorkManager is kept. */
    fun resumeInterrupted() {
        store.records.value.filter { it.state == DownloadStore.State.QUEUED || it.state == DownloadStore.State.RUNNING }.forEach { enqueue(it.id) }
    }

    /**
     * Remembers newer server positions for downloaded media, so offline playback resumes where the
     * account last listened anywhere, not only on this device.
     */
    fun adoptRemote(account: AccountIdentity, progress: List<MediaProgress>) {
        val downloaded = store.records.value.filter { it.account == account }
        for (record in downloaded) {
            val remote = progress.firstOrNull { it.libraryItemId == record.itemId && it.episodeId == record.episodeId } ?: continue
            val updated = remote.lastUpdate ?: continue
            if (record.audio.isNotEmpty()) runCatching { journal.adoptRemotePosition(account, record.itemId, record.episodeId, remote.currentTime, updated) }
        }
    }

    fun localSource(record: DownloadStore.Record, remote: MediaProgress? = null): PlaySource.Local {
        if (remote != null) adoptRemote(record.account, listOf(remote))
        val directory = File(record.directory)
        val cover = File(directory, COVER).takeIf { it.exists() }?.let { Uri.fromFile(it).toString() }
        return PlaySource.Local(
            record.account, record.itemId, record.episodeId, record.title, record.author, cover, record.mediaType,
            record.tracks, record.audio.map { Uri.fromFile(File(directory, it.name)) }, record.chapters,
            startTime = journal.cachedPosition(record.account, record.itemId, record.episodeId, newerThan = Double.NEGATIVE_INFINITY) ?: 0.0,
        )
    }

    private fun enqueue(id: String) {
        val record = store.get(id) ?: return
        val network = if (record.allowMetered && settings.current.downloadUsingCellular != CellularPolicy.NEVER) NetworkType.CONNECTED else NetworkType.UNMETERED
        val work = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setInputData(workDataOf(KEY_ID to id))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(network).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(workName(id), ExistingWorkPolicy.KEEP, work)
    }

    private fun metered() = context.getSystemService(ConnectivityManager::class.java)?.isActiveNetworkMetered == true

    /** Runs one download attempt; the return value says whether WorkManager should try again. */
    internal suspend fun run(id: String, attempt: Int, foreground: suspend (ForegroundInfo) -> Unit): Outcome = slots.withPermit {
        val record = store.get(id) ?: return Outcome.Done
        if (record.state == DownloadStore.State.COMPLETE) return Outcome.Done
        runCatching { foreground(notification(record)) }.onFailure { Log.i(TAG, "Download continues without a foreground notice: ${it.javaClass.simpleName}") }
        try {
            store.update(id) { it.copy(state = DownloadStore.State.RUNNING, error = null) }
            val client = accounts.clientFor(record.account) ?: throw Rejected("Sign in to this account again to download.")
            val directory = File(record.directory).apply { mkdirs() }
            for (part in record.parts) {
                if (part.done && File(directory, part.name).exists()) continue
                fetch(client, id, directory, part)
                store.update(id) { current -> current.copy(parts = current.parts.map { if (it.path == part.path) it.copy(done = true) else it }) }
            }
            runCatching { File(directory, COVER).writeBytes(client.bytes("api/items/${record.itemId}/cover")) }
                .onFailure { Log.i(TAG, "Cover not saved: ${it.javaClass.simpleName}") }
            store.update(id) { it.copy(state = DownloadStore.State.COMPLETE, error = null, completedAt = System.currentTimeMillis()) }
            Outcome.Done
        } catch (failure: Rejected) {
            report(com.audiobookshelf.android.data.Diagnostics.Area.MEDIA, "Download of \"${record.title}\" stopped: ${failure.message}", null)
            try { store.update(id) { it.copy(state = DownloadStore.State.FAILED, error = failure.message) } } catch (unsaved: IOException) { return Outcome.Retry }
            Outcome.Done
        } catch (failure: Exception) {
            if (failure is kotlinx.coroutines.CancellationException) throw failure
            accounts.handle(failure)
            report(com.audiobookshelf.android.data.Diagnostics.Area.MEDIA, "Download of \"${record.title}\" failed", failure)
            val message = when (failure) {
                is ApiError.SignInRequired -> "Sign in to this account again to download."
                is ApiError -> failure.message
                else -> "The connection was interrupted."
            }
            val again = attempt < MAX_ATTEMPTS && failure !is ApiError.SignInRequired
            // A state that cannot be written is retried later rather than reported as settled.
            try {
                store.update(id) { it.copy(state = if (again) DownloadStore.State.QUEUED else DownloadStore.State.FAILED, error = if (again) "$message Retrying…" else message) }
            } catch (unsaved: IOException) { return Outcome.Retry }
            if (again) Outcome.Retry else Outcome.Done
        }
    }

    private suspend fun fetch(client: ApiClient, id: String, directory: File, part: DownloadStore.Part) = withContext(Dispatchers.IO) {
        val target = File(directory, part.name)
        val staging = File(directory, part.name + ".part")
        val url = client.mediaUrl(part.path)
        var token = client.bearer()
        repeat(2) { round ->
            val offset = staging.takeIf { it.exists() }?.length() ?: 0L
            val request = okhttp3.Request.Builder().url(url).header("Authorization", "Bearer $token").header("Accept-Encoding", "identity")
                .apply { if (offset > 0) header("Range", "bytes=$offset-") }.build()
            transfer.newCall(request).await().use { response ->
                when {
                    response.code == 401 && round == 0 -> { token = client.bearerAfterRejection(token); return@repeat }
                    response.code == 401 -> throw ApiError.SignInRequired(client.account, token)
                    response.code == 416 -> {
                        if (part.size != null && offset == part.size) { staging.renameTo(target); return@withContext }
                        staging.delete(); throw IOException("Range not satisfiable")
                    }
                    response.code == 403 || response.code == 404 -> throw Rejected(ApiError.Http(response.code).message ?: "The server refused the download.")
                    !response.isSuccessful -> throw ApiError.Http(response.code)
                }
                val type = response.header("Content-Type")?.substringBefore(";")?.trim()?.lowercase()
                if (if (part.ebookFileId != null) type == "text/html" || type == "application/json" else !acceptable(type, part.mimeType)) {
                    staging.delete()
                    throw Rejected("The server sent ${type ?: "an unknown response"} instead of audio, so nothing was saved. Check your server or proxy and retry.")
                }
                val append = response.code == 206 && offset > 0
                val body = response.body ?: throw IOException("Empty response")
                var written = if (append) offset else 0L
                var reported = 0L
                FileOutputStream(staging, append).use { output ->
                    body.byteStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            written += read
                            val now = System.currentTimeMillis()
                            if (now - reported > 500) { reported = now; progress(id, part, written) }
                        }
                    }
                }
                val expected = part.size ?: body.contentLength().takeIf { it >= 0 && !append }
                if (expected != null && written != expected) {
                    staging.delete()
                    throw Rejected("The downloaded file was ${written} bytes but the server listed $expected, so it was discarded. Retry to download it again.")
                }
                if (part.ebookFormat == "pdf" && !staging.inputStream().use { input -> ByteArray(5).also { input.read(it) } }.contentEquals("%PDF-".toByteArray())) {
                    staging.delete()
                    throw Rejected("The server sent something other than the PDF, so nothing was saved. Check your server or proxy and retry.")
                }
                target.delete()
                if (!staging.renameTo(target)) throw IOException("Could not move the finished file into place")
                progress(id, part, written)
                return@withContext
            }
        }
    }

    /** Byte counts are only shown progress; the finished parts recorded separately are what resuming relies on. */
    private fun progress(id: String, part: DownloadStore.Part, written: Long) {
        runCatching {
            store.update(id) { current ->
                val finished = current.parts.takeWhile { it.path != part.path }.sumOf { it.size ?: 0L }
                current.copy(bytes = finished + written)
            }
        }
    }

    private fun acceptable(type: String?, expected: String?): Boolean = type == null || type == expected?.lowercase() ||
        type.startsWith("audio/") || type.startsWith("video/") || type == "application/octet-stream" || type == "application/ogg"

    private fun notification(record: DownloadStore.Record): ForegroundInfo {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW))
        val notice = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading ${record.title}")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .build()
        val notificationId = record.id.hashCode()
        return if (Build.VERSION.SDK_INT >= 29) ForegroundInfo(notificationId, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else ForegroundInfo(notificationId, notice)
    }

    private class Rejected(message: String) : Exception(message)

    enum class Outcome { Done, Retry }

    companion object {
        private const val TAG = "AbsDownloads"
        private const val CHANNEL = "downloads"
        private const val COVER = "cover.jpg"
        private const val MAX_ATTEMPTS = 5
        private const val MIN_FREE_BYTES = 100L * 1024 * 1024
        const val KEY_ID = "id"

        fun recordId(account: AccountIdentity, itemId: String, episodeId: String?): String {
            val digest = MessageDigest.getInstance("SHA-256").digest("${account.server}\n${account.userId}\n$itemId\n${episodeId.orEmpty()}".toByteArray())
            return digest.take(12).joinToString("") { "%02x".format(it) }
        }

        fun workName(id: String) = "download-$id"

        private fun extension(mime: String?) = when (mime?.lowercase()) {
            "audio/mpeg" -> ".mp3"
            "audio/mp4", "audio/x-m4a", "audio/m4b" -> ".m4a"
            "audio/wav", "audio/x-wav" -> ".wav"
            "audio/ogg", "application/ogg" -> ".ogg"
            "audio/flac" -> ".flac"
            "audio/aac" -> ".aac"
            else -> ""
        }
    }
}

class DownloadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val id = inputData.getString(Downloads.KEY_ID) ?: return Result.failure()
        val outcome = applicationContext.graph.downloads.run(id, runAttemptCount + 1) { setForeground(it) }
        return if (outcome == Downloads.Outcome.Retry) Result.retry() else Result.success()
    }
}
