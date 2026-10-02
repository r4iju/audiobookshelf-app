import Foundation
import RealmSwift

// Exact mirror of the legacy app's Realm schema version 21 (ios/App/Shared/models at upstream
// 0.14.2-beta). Each class persists under the legacy table name via `_realmObjectName` and stays
// out of every default schema, so these declarations can be linked into the legacy app (export)
// or the native app (in-place upgrade) without clashing with that app's own model classes.
// Opening is always read-only on a copy; property names and types must not drift from the legacy
// declarations or the copy will fail schema validation.

class LegacyRealmFileMetadata: EmbeddedObject {
    override class func _realmObjectName() -> String? { "FileMetadata" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var filename: String = ""
    @Persisted var ext: String = ""
    @Persisted var path: String = ""
    @Persisted var relPath: String = ""
    @Persisted var size: Double = 0
}

class LegacyRealmAuthor: EmbeddedObject {
    override class func _realmObjectName() -> String? { "Author" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var name: String = "Unknown"
    @Persisted var coverPath: String?
}

class LegacyRealmMetadata: EmbeddedObject {
    override class func _realmObjectName() -> String? { "Metadata" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var title: String = "Unknown"
    @Persisted var subtitle: String?
    @Persisted var authors = List<LegacyRealmAuthor>()
    @Persisted var author: String?
    @Persisted var narrators = List<String>()
    @Persisted var genres = List<String>()
    @Persisted var publishedYear: String?
    @Persisted var publishedDate: String?
    @Persisted var publisher: String?
    @Persisted var desc: String?
    @Persisted var isbn: String?
    @Persisted var asin: String?
    @Persisted var language: String?
    @Persisted var explicit: Bool = false
    @Persisted var authorName: String?
    @Persisted var authorNameLF: String?
    @Persisted var narratorName: String?
    @Persisted var seriesName: String?
    @Persisted var feedUrl: String?
}

class LegacyRealmAudioFile: EmbeddedObject {
    override class func _realmObjectName() -> String? { "AudioFile" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var index: Int?
    @Persisted var ino: String = ""
    @Persisted var metadata: LegacyRealmFileMetadata?
}

class LegacyRealmAudioTrack: EmbeddedObject {
    override class func _realmObjectName() -> String? { "AudioTrack" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var index: Int?
    @Persisted var startOffset: Double?
    @Persisted var duration: Double = 0
    @Persisted var title: String?
    @Persisted var contentUrl: String?
    @Persisted var mimeType: String = ""
    @Persisted var metadata: LegacyRealmFileMetadata?
    @Persisted var localFileId: String?
    @Persisted var serverIndex: Int?
}

class LegacyRealmChapter: EmbeddedObject {
    override class func _realmObjectName() -> String? { "Chapter" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: Int = 0
    @Persisted var start: Double = 0
    @Persisted var end: Double = 0
    @Persisted var title: String?
}

class LegacyRealmEBookFile: EmbeddedObject {
    override class func _realmObjectName() -> String? { "EBookFile" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var ino: String = ""
    @Persisted var metadata: LegacyRealmFileMetadata?
    @Persisted var ebookFormat: String = ""
    @Persisted var _contentUrl: String?
    @Persisted var localFileId: String?
}

class LegacyRealmPodcastEpisode: EmbeddedObject {
    override class func _realmObjectName() -> String? { "PodcastEpisode" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var index: Int?
    @Persisted var episode: String?
    @Persisted var episodeType: String?
    @Persisted var title: String = "Unknown"
    @Persisted var subtitle: String?
    @Persisted var desc: String?
    @Persisted var audioFile: LegacyRealmAudioFile?
    @Persisted var audioTrack: LegacyRealmAudioTrack?
    @Persisted var chapters = List<LegacyRealmChapter>()
    @Persisted var duration: Double?
    @Persisted var size: Int?
}

class LegacyRealmMediaType: EmbeddedObject {
    override class func _realmObjectName() -> String? { "MediaType" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var libraryItemId: String?
    @Persisted var metadata: LegacyRealmMetadata?
    @Persisted var coverPath: String?
    @Persisted var tags = List<String>()
    @Persisted var audioFiles = List<LegacyRealmAudioFile>()
    @Persisted var ebookFile: LegacyRealmEBookFile?
    @Persisted var chapters = List<LegacyRealmChapter>()
    @Persisted var tracks = List<LegacyRealmAudioTrack>()
    @Persisted var size: Int?
    @Persisted var duration: Double?
    @Persisted var episodes = List<LegacyRealmPodcastEpisode>()
    @Persisted var autoDownloadEpisodes: Bool?
}

class LegacyRealmMediaProgress: EmbeddedObject {
    override class func _realmObjectName() -> String? { "MediaProgress" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var userId: String = ""
    @Persisted var libraryItemId: String = ""
    @Persisted var episodeId: String?
    @Persisted var duration: Double = 0
    @Persisted var progress: Double = 0
    @Persisted var currentTime: Double = 0
    @Persisted var isFinished: Bool = false
    @Persisted var ebookLocation: String?
    @Persisted var ebookProgress: Double?
    @Persisted var lastUpdate: Double = 0
    @Persisted var startedAt: Double = 0
    @Persisted var finishedAt: Double?
}

class LegacyRealmLibraryFile: EmbeddedObject {
    override class func _realmObjectName() -> String? { "LibraryFile" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var ino: String = ""
    @Persisted var metadata: LegacyRealmFileMetadata?
}

class LegacyRealmFolder: EmbeddedObject {
    override class func _realmObjectName() -> String? { "Folder" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var fullPath: String = ""
}

class LegacyRealmLibrary: EmbeddedObject {
    override class func _realmObjectName() -> String? { "Library" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var name: String = "Unknown"
    @Persisted var folders = List<LegacyRealmFolder>()
    @Persisted var icon: String = ""
    @Persisted var mediaType: String = ""
}

class LegacyRealmUser: EmbeddedObject {
    override class func _realmObjectName() -> String? { "User" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var username: String = ""
    @Persisted var mediaProgress = List<LegacyRealmMediaProgress>()
}

class LegacyRealmLibraryItem: Object {
    override class func _realmObjectName() -> String? { "LibraryItem" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var id: String = ""
    @Persisted var ino: String = ""
    @Persisted var libraryId: String = ""
    @Persisted var folderId: String = ""
    @Persisted var path: String = ""
    @Persisted var relPath: String = ""
    @Persisted var isFile: Bool = true
    @Persisted var mtimeMs: Int = 0
    @Persisted var ctimeMs: Int = 0
    @Persisted var birthtimeMs: Int = 0
    @Persisted var addedAt: Int = 0
    @Persisted var updatedAt: Int = 0
    @Persisted var lastScan: Int?
    @Persisted var scanVersion: String?
    @Persisted var isMissing: Bool = false
    @Persisted var isInvalid: Bool = false
    @Persisted var mediaType: String = ""
    @Persisted var media: LegacyRealmMediaType?
    @Persisted var libraryFiles = List<LegacyRealmLibraryFile>()
    @Persisted var userMediaProgress: LegacyRealmMediaProgress?
}

class LegacyRealmServerConnectionConfig: Object {
    override class func _realmObjectName() -> String? { "ServerConnectionConfig" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted(indexed: true) var index: Int = 1
    @Persisted var name: String = ""
    @Persisted var address: String = ""
    @Persisted var version: String = ""
    @Persisted var userId: String = ""
    @Persisted var username: String = ""
    @Persisted var token: String = ""
}

class LegacyRealmServerConnectionConfigActiveIndex: Object {
    override class func _realmObjectName() -> String? { "ServerConnectionConfigActiveIndex" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var index: Int?
}

class LegacyRealmDeviceSettings: Object {
    override class func _realmObjectName() -> String? { "DeviceSettings" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var disableAutoRewind: Bool = false
    @Persisted var enableAltView: Bool = true
    @Persisted var allowSeekingOnMediaControls: Bool = false
    @Persisted var jumpBackwardsTime: Int = 10
    @Persisted var jumpForwardTime: Int = 10
    @Persisted var lockOrientation: String = "NONE"
    @Persisted var hapticFeedback: String = "LIGHT"
    @Persisted var languageCode: String = "en-us"
    @Persisted var downloadUsingCellular: String = "ALWAYS"
    @Persisted var streamingUsingCellular: String = "ALWAYS"
    @Persisted var disableSleepTimerFadeOut: Bool = false
}

class LegacyRealmPlayerSettings: Object {
    override class func _realmObjectName() -> String? { "PlayerSettings" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted var playbackRate: Float = 1.0
    @Persisted var chapterTrack: Bool = true
}

class LegacyRealmLogEntry: Object {
    override class func _realmObjectName() -> String? { "LogEntry" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var tag: String = ""
    @Persisted var level: String = ""
    @Persisted var message: String = ""
    @Persisted var timestamp: Int = 0
}

class LegacyRealmLocalFile: Object {
    override class func _realmObjectName() -> String? { "LocalFile" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var filename: String?
    @Persisted var _contentUrl: String = ""
    @Persisted var mimeType: String?
    @Persisted var size: Int = 0
}

class LegacyRealmLocalLibraryItem: Object {
    override class func _realmObjectName() -> String? { "LocalLibraryItem" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = "local_\(UUID().uuidString)"
    @Persisted var basePath: String = ""
    @Persisted var _contentUrl: String?
    @Persisted var isInvalid: Bool = false
    @Persisted var mediaType: String = ""
    @Persisted var media: LegacyRealmMediaType?
    @Persisted var localFiles = List<LegacyRealmLocalFile>()
    @Persisted var _coverContentUrl: String?
    @Persisted var isLocal: Bool = true
    @Persisted var serverConnectionConfigId: String?
    @Persisted var serverAddress: String?
    @Persisted var serverUserId: String?
    @Persisted(indexed: true) var libraryItemId: String?
}

class LegacyRealmLocalPodcastEpisode: Object {
    override class func _realmObjectName() -> String? { "LocalPodcastEpisode" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var index: Int = 0
    @Persisted var episode: String?
    @Persisted var episodeType: String?
    @Persisted var title: String = "Unknown"
    @Persisted var subtitle: String?
    @Persisted var desc: String?
    @Persisted var audioFile: LegacyRealmAudioFile?
    @Persisted var audioTrack: LegacyRealmAudioTrack?
    @Persisted var chapters = List<LegacyRealmChapter>()
    @Persisted var duration: Double = 0
    @Persisted var size: Int = 0
    @Persisted(indexed: true) var serverEpisodeId: String?
}

class LegacyRealmLocalMediaProgress: Object {
    override class func _realmObjectName() -> String? { "LocalMediaProgress" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = ""
    @Persisted(indexed: true) var localLibraryItemId: String = ""
    @Persisted(indexed: true) var localEpisodeId: String?
    @Persisted var duration: Double = 0
    @Persisted var progress: Double = 0
    @Persisted var currentTime: Double = 0
    @Persisted var isFinished: Bool = false
    @Persisted var ebookLocation: String?
    @Persisted var ebookProgress: Double?
    @Persisted var lastUpdate: Double = 0
    @Persisted var startedAt: Double = 0
    @Persisted var finishedAt: Double?
    @Persisted var serverConnectionConfigId: String?
    @Persisted var serverAddress: String?
    @Persisted var serverUserId: String?
    @Persisted(indexed: true) var libraryItemId: String?
    @Persisted(indexed: true) var episodeId: String?
}

class LegacyRealmPlaybackSession: Object {
    override class func _realmObjectName() -> String? { "PlaybackSession" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String = ""
    @Persisted var userId: String?
    @Persisted var libraryItemId: String?
    @Persisted var episodeId: String?
    @Persisted var mediaType: String = ""
    @Persisted var mediaMetadata: LegacyRealmMetadata?
    @Persisted var chapters = List<LegacyRealmChapter>()
    @Persisted var displayTitle: String?
    @Persisted var displayAuthor: String?
    @Persisted var coverPath: String?
    @Persisted var duration: Double = 0
    @Persisted var playMethod: Int = 0
    @Persisted var startedAt: Double?
    @Persisted var updatedAt: Double?
    @Persisted var timeListening: Double = 0
    @Persisted var audioTracks = List<LegacyRealmAudioTrack>()
    @Persisted var currentTime: Double = 0
    @Persisted var libraryItem: LegacyRealmLibraryItem?
    @Persisted var localLibraryItem: LegacyRealmLocalLibraryItem?
    @Persisted var serverConnectionConfigId: String?
    @Persisted var serverAddress: String?
    @Persisted var isActiveSession = true
    @Persisted var serverUpdatedAt: Double = 0
}

class LegacyRealmDownloadItemPart: Object {
    override class func _realmObjectName() -> String? { "DownloadItemPart" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id = ""
    @Persisted var downloadItemId: String?
    @Persisted var filename: String?
    @Persisted var fileSize: Double = 0
    @Persisted var itemTitle: String?
    @Persisted var serverPath: String?
    @Persisted var audioTrack: LegacyRealmAudioTrack?
    @Persisted var episode: LegacyRealmPodcastEpisode?
    @Persisted var ebookFile: LegacyRealmEBookFile?
    @Persisted var completed: Bool = false
    @Persisted var moved: Bool = false
    @Persisted var failed: Bool = false
    @Persisted var uri: String?
    @Persisted var destinationUri: String?
    @Persisted var progress: Double = 0
    @Persisted var bytesDownloaded: Double = 0
}

class LegacyRealmDownloadItem: Object {
    override class func _realmObjectName() -> String? { "DownloadItem" }
    override class func shouldIncludeInDefaultSchema() -> Bool { false }
    @Persisted(primaryKey: true) var id: String?
    @Persisted(indexed: true) var libraryItemId: String?
    @Persisted var episodeId: String?
    @Persisted var userMediaProgress: LegacyRealmMediaProgress?
    @Persisted var serverConnectionConfigId: String?
    @Persisted var serverAddress: String?
    @Persisted var serverUserId: String?
    @Persisted var mediaType: String?
    @Persisted var itemTitle: String?
    @Persisted var media: LegacyRealmMediaType?
    @Persisted var downloadItemParts = List<LegacyRealmDownloadItemPart>()
}

enum LegacyRealmSchema {
    static let version: UInt64 = 21

    static let objectTypes: [ObjectBase.Type] = [
        LegacyRealmFileMetadata.self, LegacyRealmAuthor.self, LegacyRealmMetadata.self, LegacyRealmAudioFile.self,
        LegacyRealmAudioTrack.self, LegacyRealmChapter.self, LegacyRealmEBookFile.self, LegacyRealmPodcastEpisode.self,
        LegacyRealmMediaType.self, LegacyRealmMediaProgress.self, LegacyRealmLibraryFile.self, LegacyRealmFolder.self,
        LegacyRealmLibrary.self, LegacyRealmUser.self, LegacyRealmLibraryItem.self, LegacyRealmServerConnectionConfig.self,
        LegacyRealmServerConnectionConfigActiveIndex.self, LegacyRealmDeviceSettings.self, LegacyRealmPlayerSettings.self,
        LegacyRealmLogEntry.self, LegacyRealmLocalFile.self, LegacyRealmLocalLibraryItem.self, LegacyRealmLocalPodcastEpisode.self,
        LegacyRealmLocalMediaProgress.self, LegacyRealmPlaybackSession.self, LegacyRealmDownloadItemPart.self, LegacyRealmDownloadItem.self,
    ]
}
