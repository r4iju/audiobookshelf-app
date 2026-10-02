import Foundation
import LegacyMigration
import RealmSwift

/// The legacy Realm's contents: credential-free snapshot plus each connection's stored access token.
public struct LegacyRealmContents {
    public let snapshot: LegacySnapshot
    public let secrets: [String: LegacyAccountSecret]
}

public enum LegacyRealmReader {
    /// Reads the legacy database through a private copy, so the original file, its lock and
    /// management files are never opened. The copy holds credentials and is removed before
    /// returning, whether or not reading succeeds. `workDirectory` belongs to the reader: copies left
    /// by a read the system interrupted are removed first.
    public static func read(realmAt url: URL, workDirectory: URL) throws -> LegacyRealmContents {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LegacyMigrationError.legacyDatabaseUnreadable("The old app's database is not present.")
        }
        for stale in (try? FileManager.default.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)) ?? [] {
            try FileManager.default.removeItem(at: stale)
        }
        let work = workDirectory.appendingPathComponent(UUID().uuidString)
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: attributes)
        defer {
            try? FileManager.default.removeItem(at: work)
            if (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: workDirectory)
            }
        }
        let copy = work.appendingPathComponent("legacy.realm")
        try FileManager.default.copyItem(at: url, to: copy)

        let version: UInt64
        do {
            version = try schemaVersionAtURL(copy)
        } catch {
            throw LegacyMigrationError.legacyDatabaseUnreadable("The old app's database could not be opened.")
        }
        guard version == LegacyRealmSchema.version else { throw LegacyMigrationError.unsupportedLegacySchema(version) }

        let configuration = Realm.Configuration(fileURL: copy, readOnly: true, schemaVersion: LegacyRealmSchema.version, objectTypes: LegacyRealmSchema.objectTypes)
        return try autoreleasepool {
            let realm: Realm
            do {
                realm = try Realm(configuration: configuration)
            } catch {
                throw LegacyMigrationError.legacyDatabaseUnreadable("The old app's database does not match the expected version 21 layout.")
            }
            defer { realm.invalidate() }
            return contents(of: realm)
        }
    }

    private static func contents(of realm: Realm) -> LegacyRealmContents {
        var secrets: [String: LegacyAccountSecret] = [:]
        let connections = realm.objects(LegacyRealmServerConnectionConfig.self).sorted(byKeyPath: "index").map { config -> LegacyConnection in
            let secret = LegacyAccountSecret(accessToken: config.token, refreshToken: nil)
            if !secret.isEmpty { secrets[config.id] = secret }
            return LegacyConnection(id: config.id, index: config.index, name: config.name, address: config.address, version: config.version, userId: config.userId, username: config.username)
        }
        let snapshot = LegacySnapshot(
            schemaVersion: LegacyRealmSchema.version,
            connections: Array(connections),
            activeConnectionIndex: realm.objects(LegacyRealmServerConnectionConfigActiveIndex.self).first?.index,
            deviceSettings: realm.objects(LegacyRealmDeviceSettings.self).first.map(deviceSettings),
            playerSettings: realm.objects(LegacyRealmPlayerSettings.self).last.map { LegacyPlayerSettings(playbackRate: $0.playbackRate, chapterTrack: $0.chapterTrack) },
            localItems: realm.objects(LegacyRealmLocalLibraryItem.self).map(localItem),
            progress: realm.objects(LegacyRealmLocalMediaProgress.self).map(progress),
            sessions: realm.objects(LegacyRealmPlaybackSession.self).map(session),
            pendingDownloads: realm.objects(LegacyRealmDownloadItem.self).map(pendingDownload)
        )
        return LegacyRealmContents(snapshot: snapshot, secrets: secrets)
    }

    private static func deviceSettings(_ row: LegacyRealmDeviceSettings) -> LegacyDeviceSettings {
        var settings = LegacyDeviceSettings()
        settings.disableAutoRewind = row.disableAutoRewind
        settings.enableAltView = row.enableAltView
        settings.allowSeekingOnMediaControls = row.allowSeekingOnMediaControls
        settings.jumpBackwardsTime = row.jumpBackwardsTime
        settings.jumpForwardTime = row.jumpForwardTime
        settings.lockOrientation = row.lockOrientation
        settings.hapticFeedback = row.hapticFeedback
        settings.languageCode = row.languageCode
        settings.downloadUsingCellular = row.downloadUsingCellular
        settings.streamingUsingCellular = row.streamingUsingCellular
        settings.disableSleepTimerFadeOut = row.disableSleepTimerFadeOut
        return settings
    }

    private static func track(_ row: LegacyRealmAudioTrack) -> LegacyTrack {
        LegacyTrack(index: row.index, localFileId: row.localFileId, title: row.title, startOffset: row.startOffset ?? 0, duration: row.duration, mimeType: row.mimeType,
                    contentUrl: row.contentUrl, serverIndex: row.serverIndex)
    }

    private static func metadata(_ row: LegacyRealmMetadata) -> LegacyMediaMetadata {
        var metadata = LegacyMediaMetadata(title: row.title)
        metadata.subtitle = row.subtitle
        metadata.authors = row.authors.map { LegacyAuthor(id: $0.id, name: $0.name) }
        metadata.author = row.author
        metadata.narrators = Array(row.narrators)
        metadata.genres = Array(row.genres)
        metadata.publishedYear = row.publishedYear
        metadata.publishedDate = row.publishedDate
        metadata.publisher = row.publisher
        metadata.description = row.desc
        metadata.isbn = row.isbn
        metadata.asin = row.asin
        metadata.language = row.language
        metadata.explicit = row.explicit
        metadata.authorName = row.authorName
        metadata.authorNameLF = row.authorNameLF
        metadata.narratorName = row.narratorName
        metadata.seriesName = row.seriesName
        metadata.feedUrl = row.feedUrl
        return metadata
    }

    private static func chapters(_ rows: List<LegacyRealmChapter>) -> [LegacyChapter] {
        rows.map { LegacyChapter(id: $0.id, start: $0.start, end: $0.end, title: $0.title) }
    }

    private static func localItem(_ row: LegacyRealmLocalLibraryItem) -> LegacyLocalItem {
        let media = row.media
        let metadata = media?.metadata
        return LegacyLocalItem(
            id: row.id, libraryItemId: row.libraryItemId, mediaType: row.mediaType,
            serverConnectionConfigId: row.serverConnectionConfigId, serverAddress: row.serverAddress, serverUserId: row.serverUserId,
            title: metadata?.title ?? "Unknown", author: metadata?.authorName ?? metadata?.author, coverPath: row._coverContentUrl,
            files: row.localFiles.map { LegacyLocalFile(id: $0.id, filename: $0.filename, path: $0._contentUrl, mimeType: $0.mimeType, size: $0.size) },
            tracks: media?.tracks.map(track) ?? [],
            chapters: media.map { chapters($0.chapters) } ?? [],
            ebook: media?.ebookFile.map { LegacyEbook(ino: $0.ino, format: $0.ebookFormat, localFileId: $0.localFileId, filename: $0.metadata?.filename) },
            episodes: media?.episodes.map {
                LegacyEpisode(id: $0.id, title: $0.title, duration: $0.duration, track: $0.audioTrack.map(track), chapters: chapters($0.chapters),
                              index: $0.index, episode: $0.episode, episodeType: $0.episodeType, subtitle: $0.subtitle, description: $0.desc, size: $0.size)
            } ?? [],
            isInvalid: row.isInvalid, basePath: row.basePath, metadata: metadata.map(Self.metadata), tags: media.map { Array($0.tags) } ?? [],
            mediaDuration: media?.duration, mediaSize: media?.size, autoDownloadEpisodes: media?.autoDownloadEpisodes
        )
    }

    private static func progress(_ row: LegacyRealmLocalMediaProgress) -> LegacyProgress {
        LegacyProgress(id: row.id, localLibraryItemId: row.localLibraryItemId, localEpisodeId: row.localEpisodeId, libraryItemId: row.libraryItemId, episodeId: row.episodeId,
                       serverConnectionConfigId: row.serverConnectionConfigId, serverAddress: row.serverAddress, serverUserId: row.serverUserId,
                       duration: row.duration, progress: row.progress, currentTime: row.currentTime, isFinished: row.isFinished,
                       ebookLocation: row.ebookLocation, ebookProgress: row.ebookProgress, lastUpdate: row.lastUpdate, startedAt: row.startedAt, finishedAt: row.finishedAt)
    }

    private static func session(_ row: LegacyRealmPlaybackSession) -> LegacySession {
        LegacySession(id: row.id, userId: row.userId, libraryItemId: row.libraryItemId, episodeId: row.episodeId, localLibraryItemId: row.localLibraryItem?.id,
                      mediaType: row.mediaType, displayTitle: row.displayTitle, displayAuthor: row.displayAuthor, duration: row.duration, playMethod: row.playMethod,
                      startedAt: row.startedAt, updatedAt: row.updatedAt, timeListening: row.timeListening, currentTime: row.currentTime,
                      serverConnectionConfigId: row.serverConnectionConfigId, serverAddress: row.serverAddress, isActiveSession: row.isActiveSession, serverUpdatedAt: row.serverUpdatedAt,
                      chapters: chapters(row.chapters), mediaMetadata: row.mediaMetadata.map(metadata), coverPath: row.coverPath)
    }

    private static func pendingDownload(_ row: LegacyRealmDownloadItem) -> LegacyPendingDownload {
        LegacyPendingDownload(id: row.id ?? "", libraryItemId: row.libraryItemId, episodeId: row.episodeId, title: row.itemTitle,
                              serverConnectionConfigId: row.serverConnectionConfigId, serverAddress: row.serverAddress, serverUserId: row.serverUserId,
                              completedParts: row.downloadItemParts.filter { $0.completed && $0.moved }.count, totalParts: row.downloadItemParts.count,
                              mediaType: row.mediaType, parts: row.downloadItemParts.map(part))
    }

    /// Never reads `uri`: the legacy downloader stored the access token in its query string.
    private static func part(_ row: LegacyRealmDownloadItemPart) -> LegacyDownloadPart {
        let role: LegacyDownloadPart.Role
        if row.filename == "cover.jpg" {
            role = .cover
        } else if row.episode != nil {
            role = .episode
        } else if row.ebookFile != nil {
            role = .ebook
        } else if row.audioTrack != nil {
            role = .track
        } else {
            role = .other
        }
        return LegacyDownloadPart(id: row.id, filename: row.filename, path: row.destinationUri, size: row.fileSize.isFinite ? Int(row.fileSize) : 0,
                                  completed: row.completed, moved: row.moved, failed: row.failed, role: role,
                                  trackIndex: row.audioTrack?.index, episodeId: row.episode?.id, ebookFormat: row.ebookFile?.ebookFormat)
    }
}
