import Foundation

/// Credential-free description of a legacy Capacitor/Realm installation (iOS Realm schema 21,
/// upstream 0.14.2-beta). Paths are relative to the legacy Documents directory, exactly as the
/// legacy downloader stored them (`<libraryItemId>/<filename>`).
public struct LegacySnapshot: Codable, Equatable {
    public static let supportedSchemaVersion: UInt64 = 21

    public var schemaVersion: UInt64
    public var connections: [LegacyConnection]
    public var activeConnectionIndex: Int?
    public var deviceSettings: LegacyDeviceSettings?
    public var playerSettings: LegacyPlayerSettings?
    /// Capacitor Preferences values (`CapacitorStorage.<key>` in UserDefaults), allowlisted.
    public var preferences: [String: String]
    /// WebView localStorage values, allowlisted (reader settings and EPUB location caches).
    public var webStorage: [String: String]
    public var localItems: [LegacyLocalItem]
    public var progress: [LegacyProgress]
    public var sessions: [LegacySession]
    /// `DownloadItem` rows: downloads still queued or running when the legacy app last ran.
    public var pendingDownloads: [LegacyPendingDownload]

    public init(schemaVersion: UInt64 = LegacySnapshot.supportedSchemaVersion, connections: [LegacyConnection] = [], activeConnectionIndex: Int? = nil, deviceSettings: LegacyDeviceSettings? = nil, playerSettings: LegacyPlayerSettings? = nil, preferences: [String: String] = [:], webStorage: [String: String] = [:], localItems: [LegacyLocalItem] = [], progress: [LegacyProgress] = [], sessions: [LegacySession] = [], pendingDownloads: [LegacyPendingDownload] = []) {
        self.schemaVersion = schemaVersion
        self.connections = connections
        self.activeConnectionIndex = activeConnectionIndex
        self.deviceSettings = deviceSettings
        self.playerSettings = playerSettings
        self.preferences = preferences
        self.webStorage = webStorage
        self.localItems = localItems
        self.progress = progress
        self.sessions = sessions
        self.pendingDownloads = pendingDownloads
    }
}

public struct LegacyPendingDownload: Codable, Equatable {
    public var id: String
    public var libraryItemId: String?
    public var episodeId: String?
    public var title: String?
    public var serverConnectionConfigId: String?
    public var serverAddress: String?
    public var serverUserId: String?
    public var completedParts: Int
    public var totalParts: Int
    public var mediaType: String?
    /// Parts already finished and moved into Documents are real downloaded files that no
    /// `LocalLibraryItem` references yet.
    public var parts: [LegacyDownloadPart]

    public init(id: String, libraryItemId: String?, episodeId: String?, title: String?, serverConnectionConfigId: String?, serverAddress: String?, serverUserId: String?, completedParts: Int, totalParts: Int, mediaType: String? = nil, parts: [LegacyDownloadPart] = []) {
        self.mediaType = mediaType
        self.parts = parts
        self.id = id
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
        self.title = title
        self.serverConnectionConfigId = serverConnectionConfigId
        self.serverAddress = serverAddress
        self.serverUserId = serverUserId
        self.completedParts = completedParts
        self.totalParts = totalParts
    }
}

/// `DownloadItemPart` without its `uri`, which embeds the access token as a query parameter.
public struct LegacyDownloadPart: Codable, Equatable {
    public enum Role: String, Codable {
        case track, episode, ebook, cover, other
    }

    public var id: String
    public var filename: String?
    /// Legacy `destinationUri`, relative to Documents.
    public var path: String?
    public var size: Int
    public var completed: Bool
    public var moved: Bool
    public var failed: Bool
    public var role: Role
    public var trackIndex: Int?
    public var episodeId: String?
    public var ebookFormat: String?

    public init(id: String, filename: String?, path: String?, size: Int, completed: Bool, moved: Bool, failed: Bool = false, role: Role, trackIndex: Int? = nil, episodeId: String? = nil, ebookFormat: String? = nil) {
        self.id = id
        self.filename = filename
        self.path = path
        self.size = size
        self.completed = completed
        self.moved = moved
        self.failed = failed
        self.role = role
        self.trackIndex = trackIndex
        self.episodeId = episodeId
        self.ebookFormat = ebookFormat
    }
}

public struct LegacyAuthor: Codable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The legacy `Metadata` embedded object, kept whole so offline display and later reconciliation
/// do not depend on the server.
public struct LegacyMediaMetadata: Codable, Equatable {
    public var title: String
    public var subtitle: String?
    public var authors: [LegacyAuthor] = []
    public var author: String?
    public var narrators: [String] = []
    public var genres: [String] = []
    public var publishedYear: String?
    public var publishedDate: String?
    public var publisher: String?
    public var description: String?
    public var isbn: String?
    public var asin: String?
    public var language: String?
    public var explicit = false
    public var authorName: String?
    public var authorNameLF: String?
    public var narratorName: String?
    public var seriesName: String?
    public var feedUrl: String?

    public init(title: String) {
        self.title = title
    }
}

/// `ServerConnectionConfig` without its `token` column. Tokens only travel as `LegacyAccountSecret`.
public struct LegacyConnection: Codable, Equatable {
    public var id: String
    public var index: Int
    public var name: String
    public var address: String
    public var version: String
    public var userId: String
    public var username: String

    public init(id: String, index: Int, name: String, address: String, version: String = "", userId: String, username: String) {
        self.id = id
        self.index = index
        self.name = name
        self.address = address
        self.version = version
        self.userId = userId
        self.username = username
    }
}

public struct LegacyDeviceSettings: Codable, Equatable {
    public var disableAutoRewind = false
    public var enableAltView = true
    public var allowSeekingOnMediaControls = false
    public var jumpBackwardsTime = 10
    public var jumpForwardTime = 10
    public var lockOrientation = "NONE"
    public var hapticFeedback = "LIGHT"
    public var languageCode = "en-us"
    public var downloadUsingCellular = "ALWAYS"
    public var streamingUsingCellular = "ALWAYS"
    public var disableSleepTimerFadeOut = false

    public init() {}
}

public struct LegacyPlayerSettings: Codable, Equatable {
    public var playbackRate: Float
    public var chapterTrack: Bool

    public init(playbackRate: Float = 1, chapterTrack: Bool = true) {
        self.playbackRate = playbackRate
        self.chapterTrack = chapterTrack
    }
}

public struct LegacyLocalFile: Codable, Equatable {
    public var id: String
    public var filename: String?
    /// Legacy `_contentUrl`, relative to Documents.
    public var path: String
    public var mimeType: String?
    /// Size recorded by the legacy downloader when the file completed.
    public var size: Int

    public init(id: String, filename: String?, path: String, mimeType: String?, size: Int) {
        self.id = id
        self.filename = filename
        self.path = path
        self.mimeType = mimeType
        self.size = size
    }
}

public struct LegacyTrack: Codable, Equatable {
    public var index: Int?
    public var localFileId: String?
    public var title: String?
    public var startOffset: Double
    public var duration: Double
    public var mimeType: String
    public var contentUrl: String?
    public var serverIndex: Int?

    public init(index: Int?, localFileId: String?, title: String? = nil, startOffset: Double, duration: Double, mimeType: String, contentUrl: String? = nil, serverIndex: Int? = nil) {
        self.serverIndex = serverIndex
        self.index = index
        self.localFileId = localFileId
        self.title = title
        self.startOffset = startOffset
        self.duration = duration
        self.mimeType = mimeType
        self.contentUrl = contentUrl
    }
}

public struct LegacyEbook: Codable, Equatable {
    public var ino: String
    /// Server `ebookFormat`: pdf, epub, mobi, azw3, cbz, cbr.
    public var format: String
    public var localFileId: String?
    public var filename: String?

    public init(ino: String, format: String, localFileId: String?, filename: String?) {
        self.ino = ino
        self.format = format
        self.localFileId = localFileId
        self.filename = filename
    }
}

public struct LegacyChapter: Codable, Equatable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var title: String?

    public init(id: Int, start: Double, end: Double, title: String?) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
    }
}

public struct LegacyEpisode: Codable, Equatable {
    public var id: String
    public var title: String
    public var duration: Double?
    public var track: LegacyTrack?
    public var chapters: [LegacyChapter]
    public var index: Int?
    public var episode: String?
    public var episodeType: String?
    public var subtitle: String?
    public var description: String?
    public var size: Int?

    public init(id: String, title: String, duration: Double?, track: LegacyTrack?, chapters: [LegacyChapter] = [], index: Int? = nil, episode: String? = nil, episodeType: String? = nil, subtitle: String? = nil, description: String? = nil, size: Int? = nil) {
        self.index = index
        self.episode = episode
        self.episodeType = episodeType
        self.subtitle = subtitle
        self.description = description
        self.size = size
        self.id = id
        self.title = title
        self.duration = duration
        self.track = track
        self.chapters = chapters
    }
}

/// `LocalLibraryItem` with the media fields needed to play, read and re-associate it.
public struct LegacyLocalItem: Codable, Equatable {
    public var id: String
    public var libraryItemId: String?
    public var mediaType: String
    public var serverConnectionConfigId: String?
    public var serverAddress: String?
    public var serverUserId: String?
    public var title: String
    public var author: String?
    public var coverPath: String?
    public var files: [LegacyLocalFile]
    public var tracks: [LegacyTrack]
    public var chapters: [LegacyChapter]
    public var ebook: LegacyEbook?
    public var episodes: [LegacyEpisode]
    /// The legacy app marked the item unusable; kept as it was.
    public var isInvalid: Bool
    public var basePath: String?
    public var metadata: LegacyMediaMetadata?
    public var tags: [String]
    public var mediaDuration: Double?
    public var mediaSize: Int?
    public var autoDownloadEpisodes: Bool?

    public init(id: String, libraryItemId: String?, mediaType: String, serverConnectionConfigId: String?, serverAddress: String?, serverUserId: String?, title: String, author: String? = nil, coverPath: String? = nil, files: [LegacyLocalFile], tracks: [LegacyTrack] = [], chapters: [LegacyChapter] = [], ebook: LegacyEbook? = nil, episodes: [LegacyEpisode] = [], isInvalid: Bool = false, basePath: String? = nil, metadata: LegacyMediaMetadata? = nil, tags: [String] = [], mediaDuration: Double? = nil, mediaSize: Int? = nil, autoDownloadEpisodes: Bool? = nil) {
        self.isInvalid = isInvalid
        self.basePath = basePath
        self.metadata = metadata
        self.tags = tags
        self.mediaDuration = mediaDuration
        self.mediaSize = mediaSize
        self.autoDownloadEpisodes = autoDownloadEpisodes
        self.id = id
        self.libraryItemId = libraryItemId
        self.mediaType = mediaType
        self.serverConnectionConfigId = serverConnectionConfigId
        self.serverAddress = serverAddress
        self.serverUserId = serverUserId
        self.title = title
        self.author = author
        self.coverPath = coverPath
        self.files = files
        self.tracks = tracks
        self.chapters = chapters
        self.ebook = ebook
        self.episodes = episodes
    }
}

/// `LocalMediaProgress`: the device-held listening and reading position for a downloaded item.
public struct LegacyProgress: Codable, Equatable {
    public var id: String
    public var localLibraryItemId: String
    public var localEpisodeId: String?
    public var libraryItemId: String?
    public var episodeId: String?
    public var serverConnectionConfigId: String?
    public var serverAddress: String?
    public var serverUserId: String?
    public var duration: Double
    public var progress: Double
    public var currentTime: Double
    public var isFinished: Bool
    public var ebookLocation: String?
    public var ebookProgress: Double?
    public var lastUpdate: Double
    public var startedAt: Double
    public var finishedAt: Double?

    public init(id: String, localLibraryItemId: String, localEpisodeId: String? = nil, libraryItemId: String?, episodeId: String? = nil, serverConnectionConfigId: String?, serverAddress: String?, serverUserId: String?, duration: Double, progress: Double, currentTime: Double, isFinished: Bool = false, ebookLocation: String? = nil, ebookProgress: Double? = nil, lastUpdate: Double, startedAt: Double, finishedAt: Double? = nil) {
        self.id = id
        self.localLibraryItemId = localLibraryItemId
        self.localEpisodeId = localEpisodeId
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
        self.serverConnectionConfigId = serverConnectionConfigId
        self.serverAddress = serverAddress
        self.serverUserId = serverUserId
        self.duration = duration
        self.progress = progress
        self.currentTime = currentTime
        self.isFinished = isFinished
        self.ebookLocation = ebookLocation
        self.ebookProgress = ebookProgress
        self.lastUpdate = lastUpdate
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// A `PlaybackSession` row. The legacy app deletes rows once the server accepted them, so every
/// row present is listening the server may not have received.
public struct LegacySession: Codable, Equatable {
    public var id: String
    public var userId: String?
    public var libraryItemId: String?
    public var episodeId: String?
    public var localLibraryItemId: String?
    public var mediaType: String
    public var displayTitle: String?
    public var displayAuthor: String?
    public var duration: Double
    public var playMethod: Int
    public var startedAt: Double?
    public var updatedAt: Double?
    public var timeListening: Double
    public var currentTime: Double
    public var serverConnectionConfigId: String?
    public var serverAddress: String?
    public var isActiveSession: Bool
    public var serverUpdatedAt: Double
    public var chapters: [LegacyChapter]
    public var mediaMetadata: LegacyMediaMetadata?
    public var coverPath: String?

    public init(id: String, userId: String?, libraryItemId: String?, episodeId: String? = nil, localLibraryItemId: String?, mediaType: String, displayTitle: String? = nil, displayAuthor: String? = nil, duration: Double, playMethod: Int, startedAt: Double?, updatedAt: Double?, timeListening: Double, currentTime: Double, serverConnectionConfigId: String?, serverAddress: String?, isActiveSession: Bool, serverUpdatedAt: Double = 0, chapters: [LegacyChapter] = [], mediaMetadata: LegacyMediaMetadata? = nil, coverPath: String? = nil) {
        self.chapters = chapters
        self.mediaMetadata = mediaMetadata
        self.coverPath = coverPath
        self.id = id
        self.userId = userId
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
        self.localLibraryItemId = localLibraryItemId
        self.mediaType = mediaType
        self.displayTitle = displayTitle
        self.displayAuthor = displayAuthor
        self.duration = duration
        self.playMethod = playMethod
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.timeListening = timeListening
        self.currentTime = currentTime
        self.serverConnectionConfigId = serverConnectionConfigId
        self.serverAddress = serverAddress
        self.isActiveSession = isActiveSession
        self.serverUpdatedAt = serverUpdatedAt
    }
}

/// Which legacy storage keys may cross the migration boundary. Anything else (notably the WebView
/// `device` blob and `refresh_token_<id>` entries, which hold credentials) is dropped.
public enum LegacyStorageAllowlist {
    public static let preferenceKeys: Set<String> = ["userSettings", "serverSettings", "playerSettings", "bookshelfListView", "lastLibraryId", "theme", "lang"]
    public static let webStorageKeys: Set<String> = ["ereaderSettings", "absDeviceId"]
    public static let webStoragePrefixes = ["ebookLocations-"]

    public static func preferences(_ values: [String: String]) -> [String: String] {
        values.filter { preferenceKeys.contains($0.key) }
    }

    public static func webStorage(_ values: [String: String]) -> [String: String] {
        values.filter { key, _ in webStorageKeys.contains(key) || webStoragePrefixes.contains { key.hasPrefix($0) } }
    }

    /// An archive leaves the device, so it also omits the server settings cache (fetched again at
    /// sign-in) and the device identity (the receiving app is another installation).
    public static let archiveExclusions: Set<String> = ["serverSettings", "absDeviceId"]

    public static func archivePreferences(_ values: [String: String]) -> [String: String] {
        preferences(values).filter { !archiveExclusions.contains($0.key) }
    }

    public static func archiveWebStorage(_ values: [String: String]) -> [String: String] {
        webStorage(values).filter { !archiveExclusions.contains($0.key) }
    }
}
