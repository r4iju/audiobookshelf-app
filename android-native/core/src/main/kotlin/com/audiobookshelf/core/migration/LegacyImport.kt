package com.audiobookshelf.core.migration

import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.AccountIdentity
import com.audiobookshelf.core.ServerAddress
import com.audiobookshelf.core.writeAtomically
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.security.MessageDigest

@Serializable data class Issue(val kind: Kind, val title: String? = null, val detail: String) {
    enum class Kind { FILE_MISSING, FILE_CORRUPT, ACCOUNT_MISMATCH, UNSCOPED, UNREADABLE_CONNECTION, ITEM_CHANGED }
}

@Serializable data class ImportedAccount(val identity: AccountIdentity, val name: String, val username: String)

@Serializable data class StagedFile(
    val legacyPath: String,
    val name: String,
    val mimeType: String?,
    val size: Long,
    val digest: String,
    val ebookFormat: String? = null,
    val ebookIno: String? = null,
    /** The track's index as the legacy app recorded it; for a running download, the server's index. */
    val trackIndex: Int? = null,
)

@Serializable data class ImportedTitle(
    val account: AccountIdentity,
    val itemId: String,
    val episodeId: String?,
    val title: String,
    val author: String,
    val mediaType: String,
    val files: List<StagedFile>,
    /** Some files are not on this device (a running download, or files removed): they are downloaded again. */
    val partial: Boolean = false,
    val attached: Boolean = false,
) {
    val audio get() = files.filter { it.ebookFormat == null }.sortedBy { it.trackIndex ?: 0 }
    val ebook get() = files.firstOrNull { it.ebookFormat != null }
}

@Serializable data class ImportedSession(val account: AccountIdentity, val session: LegacySession, val attached: Boolean = false)
@Serializable data class ImportedProgress(val account: AccountIdentity, val progress: LegacyProgress, val attached: Boolean = false)

/** What was committed. Account data attaches only once that same account signs in on this device. */
@Serializable data class Outcome(
    val fingerprint: String,
    val archiveCreatedAt: Long?,
    val accounts: List<ImportedAccount>,
    val titles: List<ImportedTitle>,
    val sessions: List<ImportedSession>,
    val progress: List<ImportedProgress>,
    val preferences: Map<String, String>,
    val webStorage: Map<String, String>,
    val deviceSettings: JsonObject?,
    val issues: List<Issue>,
    val settingsApplied: Boolean = false,
)

data class PlannedAccount(val identity: AccountIdentity, val name: String, val username: String, val signedIn: Boolean)
data class PlannedTitle(val account: AccountIdentity, val itemId: String, val episodeId: String?, val title: String, val bytes: Long, val partial: Boolean)

data class Plan(val accounts: List<PlannedAccount>, val titles: List<PlannedTitle>, val issues: List<Issue>, val requiredBytes: Long, val availableBytes: Long, val settings: Boolean) {
    val fits get() = requiredBytes <= availableBytes
}

/**
 * Imports a [LegacyArchive] into [root]. Preflight only reads. The import copies each file into
 * `staging/<sha256>` and checks it against the archive's digest, recording every verified file in
 * `state.json` so an interrupted import continues where it stopped. Writing `outcome.json` commits it;
 * an archive is imported once, and a different one is refused afterwards. The archive and the legacy
 * installation are never changed.
 */
class LegacyImport(private val root: File) {
    @Serializable private data class State(val fingerprint: String, val verified: Map<String, String> = emptyMap(), val corrupt: Set<String> = emptySet())

    private class Resolution(val account: AccountIdentity?, val issue: Issue.Kind?)

    private class Candidate(val title: ImportedTitle, val missing: Boolean)

    private val stateFile get() = File(root, "state.json")
    private val outcomeFile get() = File(root, "outcome.json")
    private val staging get() = File(root, "staging")

    fun preflight(archive: LegacyArchive, signedIn: Set<AccountIdentity>, availableBytes: Long): Plan {
        val snapshot = archive.manifest.snapshot
        val (candidates, issues) = candidates(archive)
        val accounts = accounts(snapshot).map { PlannedAccount(it.identity, it.name, it.username, it.identity in signedIn) }
        val titles = candidates.map { PlannedTitle(it.title.account, it.title.itemId, it.title.episodeId, it.title.title, it.title.files.sumOf { file -> file.size }, it.title.partial) }
        val required = candidates.flatMap { it.title.files }.distinctBy { it.legacyPath }.sumOf { it.size }
        return Plan(accounts, titles, issues, required, availableBytes, snapshot.device.deviceSettings != null || snapshot.preferences.isNotEmpty())
    }

    fun run(archive: LegacyArchive, copied: (String) -> Unit = {}): Outcome {
        outcome()?.let { committed -> if (committed.fingerprint == archive.fingerprint) return committed else throw MigrationError.AnotherArchiveImported() }
        root.mkdirs()
        var state = readState()?.takeIf { it.fingerprint == archive.fingerprint }
            ?: State(archive.fingerprint).also { staging.deleteRecursively(); saveState(it) }
        val (candidates, issues) = candidates(archive)
        val files = candidates.flatMap { it.title.files }.distinctBy { it.legacyPath }
        val needed = files.filterNot { state.verified[it.legacyPath] == it.digest && staged(it).exists() || it.legacyPath in state.corrupt }
        val available = root.usableSpace
        if (needed.sumOf { it.size } > available) throw MigrationError.InsufficientSpace(needed.sumOf { it.size }, available)
        staging.mkdirs()
        for (file in needed) {
            val stored = archive.manifest.storedPaths[file.legacyPath] ?: throw MigrationError.Unreadable()
            val temporary = File(staging, "${file.digest}.tmp")
            val digest = MessageDigest.getInstance("SHA-256")
            archive.read(stored) { input ->
                temporary.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 16)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                    output.fd.sync()
                }
            }
            if (hex(digest.digest()) == file.digest && temporary.renameTo(staged(file))) {
                state = state.copy(verified = state.verified + (file.legacyPath to file.digest))
                saveState(state)
                copied(file.legacyPath)
            } else {
                temporary.delete()
                state = state.copy(corrupt = state.corrupt + file.legacyPath)
                saveState(state)
            }
        }

        val corrupt = candidates.filter { candidate -> candidate.title.files.any { it.legacyPath in state.corrupt } }
        val adopted = candidates - corrupt.toSet()
        val snapshot = archive.manifest.snapshot
        val resolver = resolver(snapshot)
        val sessions = snapshot.playbackSessions.mapNotNull { session ->
            val resolved = resolver(session.serverConnectionConfigId, session.serverAddress, session.userId)
            resolved.account?.takeIf { session.libraryItemId != null }?.let { ImportedSession(it, session) }
        }
        val progress = snapshot.localMediaProgress.mapNotNull { entry ->
            val resolved = resolver(entry.serverConnectionConfigId, entry.serverAddress, entry.serverUserId)
            resolved.account?.takeIf { entry.libraryItemId != null }?.let { ImportedProgress(it, entry) }
        }
        val outcome = Outcome(
            fingerprint = archive.fingerprint,
            archiveCreatedAt = archive.manifest.createdAt,
            accounts = accounts(snapshot),
            titles = adopted.map { it.title },
            sessions = sessions,
            progress = progress,
            preferences = snapshot.preferences,
            webStorage = snapshot.webStorage,
            deviceSettings = snapshot.device.deviceSettings,
            issues = issues + corrupt.map { Issue(Issue.Kind.FILE_CORRUPT, it.title.title, "A file did not match the export, so this title is not adopted. Download it again.") },
        )
        save(outcome)
        stateFile.delete()
        // Files only a refused title used are not needed.
        val kept = outcome.titles.flatMap { it.files }.map { it.digest }.toSet()
        staging.listFiles()?.filter { it.name !in kept }?.forEach { it.delete() }
        return outcome
    }

    fun outcome(): Outcome? = outcomeFile.takeIf { it.exists() }?.let { AbsJson.decodeFromString(Outcome.serializer(), it.readText()) }

    /** Records [outcome] as the committed import, for marking what has been attached. */
    fun save(outcome: Outcome) = writeAtomically(outcomeFile, AbsJson.encodeToString(Outcome.serializer(), outcome).toByteArray())

    /** An import stopped before it was committed; choosing the same export again continues it. */
    val interrupted get() = stateFile.exists() && !outcomeFile.exists()

    fun staged(file: StagedFile): File = File(staging, file.digest)

    /** Removes staged files no title still waiting for its account needs. */
    fun releaseAttached() {
        val outcome = outcome() ?: return
        val waiting = outcome.titles.filterNot { it.attached }.flatMap { it.files }.map { it.digest }.toSet()
        staging.listFiles()?.filter { it.name !in waiting }?.forEach { it.delete() }
    }

    private fun accounts(snapshot: LegacySnapshot) = snapshot.device.serverConnectionConfigs.sortedBy { it.index }.mapNotNull { connection ->
        identity(connection)?.let { ImportedAccount(it, connection.name, connection.username) }
    }

    private fun identity(connection: LegacyConnection) =
        runCatching { AccountIdentity(ServerAddress.parse(connection.address).canonical, connection.userId) }.getOrNull()

    /** A row belongs to its connection's account only when its own server and user agree with it. */
    private fun resolver(snapshot: LegacySnapshot): (String?, String?, String?) -> Resolution {
        val connections = snapshot.device.serverConnectionConfigs.associateBy { it.id }
        return resolve@{ connectionId, address, userId ->
            val connection = connectionId?.let(connections::get) ?: return@resolve Resolution(null, Issue.Kind.ACCOUNT_MISMATCH)
            val account = identity(connection) ?: return@resolve Resolution(null, Issue.Kind.UNREADABLE_CONNECTION)
            val rowServer = address?.let { runCatching { ServerAddress.parse(it).canonical }.getOrNull() ?: "" }
            if (rowServer != null && rowServer != account.server || userId != null && userId != account.userId) Resolution(null, Issue.Kind.ACCOUNT_MISMATCH)
            else Resolution(account, null)
        }
    }

    private fun candidates(archive: LegacyArchive): Pair<List<Candidate>, List<Issue>> {
        val manifest = archive.manifest
        val snapshot = manifest.snapshot
        val resolve = resolver(snapshot)
        val issues = mutableListOf<Issue>()
        snapshot.device.serverConnectionConfigs.filter { identity(it) == null }.forEach {
            issues += Issue(Issue.Kind.UNREADABLE_CONNECTION, it.name, "The server address ${it.address} could not be read, so its data is not adopted.")
        }
        val candidates = mutableListOf<Candidate>()

        fun staged(path: String, name: String, mimeType: String?, size: Long, ebook: LegacyEbook? = null, trackIndex: Int? = null): StagedFile? =
            manifest.digests[path]?.let { StagedFile(path, name, mimeType, size, it, ebook?.ebookFormat?.lowercase(), ebook?.ino, trackIndex) }

        fun propose(account: Resolution, itemId: String?, episodeId: String?, title: String, author: String, mediaType: String, wanted: List<Pair<String, () -> StagedFile?>>, partial: Boolean) {
            when {
                itemId == null -> issues += Issue(Issue.Kind.UNSCOPED, title, "This title is not linked to a server, so it is not adopted. Its files stay in the previous app.")
                account.account == null -> issues += Issue(account.issue!!, title, "This title was saved for a different account than its server's, so it is kept aside and not attached.")
                else -> {
                    val files = wanted.mapNotNull { it.second() }
                    if (files.isEmpty()) {
                        issues += Issue(Issue.Kind.FILE_MISSING, title, "Its files were no longer on the device when the export was made.")
                        return
                    }
                    if (files.size < wanted.size) issues += Issue(Issue.Kind.FILE_MISSING, title, "Some files were missing from the export; they are downloaded again.")
                    candidates += Candidate(ImportedTitle(account.account, itemId, episodeId, title, author, mediaType, files, partial || files.size < wanted.size), missing = files.size < wanted.size)
                }
            }
        }

        for (item in snapshot.localLibraryItems) {
            val account = resolve(item.serverConnectionConfigId, item.serverAddress, item.serverUserId)
            val byId = item.localFiles.associateBy { it.id }
            fun pathOf(file: LegacyFile) = file.contentUrl.takeIf { it.startsWith("content:") } ?: file.absolutePath
            fun nameOf(file: LegacyFile) = file.filename ?: File(file.absolutePath).name
            val heading = item.media.metadata.title
            if (item.mediaType == "podcast") {
                for (episode in item.media.episodes.orEmpty()) {
                    val file = episode.audioTrack?.localFileId?.let(byId::get) ?: continue
                    propose(account, item.libraryItemId, episode.serverEpisodeId ?: if (item.libraryItemId == null) null else episode.id, episode.title ?: heading, heading, "podcast",
                        listOf(pathOf(file) to { staged(pathOf(file), nameOf(file), file.mimeType, file.size, trackIndex = 0) }), partial = false)
                }
            } else {
                val audio = item.media.tracks.orEmpty().sortedBy { it.index }.mapNotNull { track -> track.localFileId?.let(byId::get)?.let { track to it } }
                val wanted = audio.map { (track, file) -> pathOf(file) to { staged(pathOf(file), nameOf(file), file.mimeType ?: track.mimeType, file.size, trackIndex = track.index) } } +
                    listOfNotNull(item.media.ebookFile?.let { ebook ->
                        ebook.localFileId?.let(byId::get)?.let { file -> pathOf(file) to { staged(pathOf(file), nameOf(file), file.mimeType, file.size, ebook) } }
                    })
                propose(account, item.libraryItemId, null, heading, item.media.metadata.authorName ?: item.media.metadata.author.orEmpty(), item.mediaType, wanted, partial = false)
            }
        }

        val adopted = candidates.map { it.title.account to (it.title.itemId to it.title.episodeId) }.toSet()
        for (download in snapshot.downloadItems) {
            val account = resolve(download.serverConnectionConfigId, download.serverAddress, download.serverUserId)
            if (account.account to (download.libraryItemId to download.episodeId) in adopted) continue
            val finished = download.downloadItemParts.filter { it.completed && it.moved && it.finalDestinationPath in manifest.digests }
            if (finished.isEmpty()) continue
            val wanted = finished.map { part ->
                part.finalDestinationPath to { staged(part.finalDestinationPath, part.filename, null, part.fileSize, part.ebookFile, part.audioTrack?.index ?: part.episode?.audioTrack?.index) }
            }
            propose(account, download.libraryItemId, download.episodeId, download.itemTitle, "", download.mediaType, wanted, partial = true)
        }
        return candidates to issues
    }

    private fun readState(): State? = stateFile.takeIf { it.exists() }?.let { runCatching { AbsJson.decodeFromString(State.serializer(), it.readText()) }.getOrNull() }

    private fun saveState(state: State) = writeAtomically(stateFile, AbsJson.encodeToString(State.serializer(), state).toByteArray())

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}
