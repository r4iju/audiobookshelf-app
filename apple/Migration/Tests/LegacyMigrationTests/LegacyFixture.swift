import CryptoKit
import Foundation
import LegacyMigration

/// A synthetic legacy installation: Documents tree with downloaded media plus the snapshot that the
/// Realm reader would produce for it. Every value is invented; tokens are recognisable markers so
/// tests can prove they never reach disk.
struct LegacyFixture {
    static let accessMarker = "SYNTHETIC-ACCESS-TOKEN"
    static let refreshMarker = "SYNTHETIC-REFRESH-TOKEN"

    let directory: URL
    let documents: URL
    var snapshot: LegacySnapshot

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-fixture-\(UUID().uuidString)")
        documents = directory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        snapshot = LegacySnapshot()
        try build()
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func migrationRoot(_ name: String = "root") -> URL {
        directory.appendingPathComponent("NativeContainer/\(name)")
    }

    var inPlaceSource: LegacySource {
        LegacySource(kind: .inPlace, snapshot: snapshot, filesRoot: documents, secrets: FixtureSecrets())
    }

    @discardableResult
    func writeFile(_ path: String, _ contents: String) throws -> LegacyLocalFile {
        let url = documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(contents.utf8)
        try data.write(to: url)
        let name = (path as NSString).lastPathComponent
        return LegacyLocalFile(id: "\(path.split(separator: "/")[0])_\(Data(name.utf8).base64EncodedString())", filename: name, path: path, mimeType: Self.mime(name), size: data.count)
    }

    static func mime(_ name: String) -> String {
        switch (name as NSString).pathExtension {
        case "mp3": return "audio/mpeg"
        case "jpg": return "image/jpeg"
        case "pdf": return "application/pdf"
        case "epub": return "application/epub+zip"
        default: return "application/octet-stream"
        }
    }

    /// Byte-level digest of every legacy file, used to prove the source is untouched.
    func legacyTreeDigest() throws -> [String: String] {
        var result: [String: String] = [:]
        let base = directory.resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator where !url.path.contains("/NativeContainer/") {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(url.resolvingSymlinksInPath().path.dropFirst(base.path.count))] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    private mutating func build() throws {
        snapshot.connections = [
            LegacyConnection(id: "conn-a1", index: 1, name: "Home", address: "https://Books.Example.test:443/abs/", version: "2.30.0", userId: "user-1", username: "alice"),
            LegacyConnection(id: "conn-a2", index: 2, name: "Home (Bob)", address: "https://books.example.test/abs", version: "2.30.0", userId: "user-2", username: "bob"),
            LegacyConnection(id: "conn-b1", index: 3, name: "LAN", address: "http://192.168.0.20:13378", userId: "user-1", username: "alice"),
            LegacyConnection(id: "conn-a1-dup", index: 4, name: "Home again", address: "https://books.example.test/abs", userId: "user-1", username: "alice"),
        ]
        snapshot.activeConnectionIndex = 2
        var device = LegacyDeviceSettings()
        device.jumpForwardTime = 30
        device.jumpBackwardsTime = 15
        device.lockOrientation = "PORTRAIT"
        device.hapticFeedback = "HEAVY"
        device.languageCode = "de"
        device.downloadUsingCellular = "NEVER"
        device.disableSleepTimerFadeOut = true
        snapshot.deviceSettings = device
        snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1.35, chapterTrack: false)
        snapshot.preferences = [
            "playerSettings": #"{"playbackRate":1.35,"useChapterTrack":false}"#,
            "bookshelfListView": "1",
            "lastLibraryId": "lib-books",
            "theme": "black",
            "lang": "de",
            "unrelatedPlugin": "ignored",
        ]
        snapshot.webStorage = [
            "ereaderSettings": #"{"theme":"sepia","fontScale":1.2,"lineSpacing":1.6,"textStroke":0,"spread":"none","navigateWithVolume":"enabled"}"#,
            "ebookLocations-li-epub": #"{"lastAccessed":1759300000000,"locations":"[\"epubcfi(/6/2)\"]"}"#,
            "absDeviceId": "legacy-device-1",
            "device": #"{"serverConnectionConfigs":[{"token":"\#(Self.accessMarker)-a1"}]}"#,
            "refresh_token_conn-a1": "\(Self.refreshMarker)-a1",
        ]

        let audioA = try writeFile("li-audio/01 Opening.mp3", "audio-track-one")
        let audioB = try writeFile("li-audio/02 Middle.mp3", "audio-track-two-longer")
        _ = try writeFile("li-audio/cover.jpg", "cover-bytes")
        let pdf = try writeFile("li-pdf/companion.pdf", "%PDF-1.7 synthetic")
        let epub = try writeFile("li-epub/book.epub", "PK-epub-synthetic")
        let mobi = try writeFile("li-mobi/book.mobi", "BOOKMOBI-synthetic")
        let azw3 = try writeFile("li-azw3/book.azw3", "AZW3-synthetic")
        let cbz = try writeFile("li-cbz/comic.cbz", "PK-cbz-synthetic")
        let cbr = try writeFile("li-cbr/comic.cbr", "Rar!-cbr-synthetic")
        let badPdf = try writeFile("li-pdf-bad/broken-location.pdf", "%PDF-1.4 synthetic")
        let episode = try writeFile("li-pod/ep1.mp3", "episode-audio")
        var truncated = try writeFile("li-trunc/part.mp3", "short")
        truncated.size = 4096
        let missing = LegacyLocalFile(id: "li-missing_bWlzc2luZw==", filename: "gone.mp3", path: "li-missing/gone.mp3", mimeType: "audio/mpeg", size: 100)
        let orphan = try writeFile("li-orphan/orphan.mp3", "orphan-audio")
        let removed = try writeFile("li-removed/removed.mp3", "removed-server-audio")

        func book(_ id: String, _ connection: String?, tracks: [LegacyLocalFile] = [], ebook: (LegacyLocalFile, String)? = nil, cover: String? = nil, address: String? = nil, user: String? = nil) -> LegacyLocalItem {
            let conn = snapshot.connections.first { $0.id == connection }
            return LegacyLocalItem(
                id: "local_\(id)", libraryItemId: id, mediaType: "book", serverConnectionConfigId: connection,
                serverAddress: address ?? conn?.address, serverUserId: user ?? conn?.userId,
                title: "Title \(id)", author: "Author \(id)", coverPath: cover,
                files: tracks + (ebook.map { [$0.0] } ?? []),
                tracks: tracks.enumerated().map { LegacyTrack(index: $0.offset + 1, localFileId: $0.element.id, title: $0.element.filename, startOffset: Double($0.offset) * 100, duration: 100, mimeType: "audio/mpeg") },
                chapters: tracks.isEmpty ? [] : [LegacyChapter(id: 0, start: 0, end: 200, title: "Chapter 1")],
                ebook: ebook.map { LegacyEbook(ino: "ino-\(id)", format: $0.1, localFileId: $0.0.id, filename: $0.0.filename) }
            )
        }

        snapshot.localItems = [
            book("li-audio", "conn-a1", tracks: [audioA, audioB], cover: "li-audio/cover.jpg"),
            book("li-pdf", "conn-a2", ebook: (pdf, "pdf")),
            book("li-epub", "conn-a1", ebook: (epub, "epub")),
            book("li-mobi", "conn-a1", ebook: (mobi, "mobi")),
            book("li-azw3", "conn-a1", ebook: (azw3, "azw3")),
            book("li-cbz", "conn-a1", ebook: (cbz, "cbz")),
            book("li-cbr", "conn-a1", ebook: (cbr, "cbr")),
            book("li-pdf-bad", "conn-a1", ebook: (badPdf, "pdf")),
            book("li-trunc", "conn-a1", tracks: [truncated]),
            book("li-missing", "conn-a1", tracks: [missing]),
            book("li-orphan", nil, tracks: [orphan]),
            book("li-removed", "conn-gone", tracks: [removed], address: "https://old.example.test", user: "user-9"),
            LegacyLocalItem(
                id: "local_li-pod", libraryItemId: "li-pod", mediaType: "podcast", serverConnectionConfigId: "conn-b1",
                serverAddress: "http://192.168.0.20:13378", serverUserId: "user-1", title: "Synthetic Podcast", files: [episode],
                episodes: [LegacyEpisode(id: "ep-1", title: "Episode One", duration: 60, track: LegacyTrack(index: 1, localFileId: episode.id, startOffset: 0, duration: 60, mimeType: "audio/mpeg"))]
            ),
        ]

        func progress(_ item: String, _ connection: String?, time: Double = 0, location: String? = nil, fraction: Double? = nil, episode: String? = nil) -> LegacyProgress {
            let local = snapshot.localItems.first { $0.libraryItemId == item }!
            return LegacyProgress(
                id: episode.map { "\(local.id)-\($0)" } ?? local.id, localLibraryItemId: local.id, localEpisodeId: episode,
                libraryItemId: item, episodeId: episode, serverConnectionConfigId: connection,
                serverAddress: local.serverAddress, serverUserId: local.serverUserId,
                duration: 200, progress: time / 200, currentTime: time, ebookLocation: location, ebookProgress: fraction,
                lastUpdate: 1_759_300_000_000, startedAt: 1_759_200_000_000
            )
        }
        snapshot.progress = [
            progress("li-audio", "conn-a1", time: 123.5),
            progress("li-pdf", "conn-a2", location: "12", fraction: 0.3),
            progress("li-epub", "conn-a1", location: "epubcfi(/6/14!/4/2/1:0)", fraction: 0.42),
            progress("li-mobi", "conn-a1", location: "loc-1520", fraction: 0.1),
            progress("li-azw3", "conn-a1", location: "kindle-pos:88", fraction: 0.2),
            progress("li-cbz", "conn-a1", location: "7", fraction: 0.5),
            progress("li-cbr", "conn-a1", location: "3", fraction: 0.25),
            progress("li-pdf-bad", "conn-a1", location: "chapter-3", fraction: 0.6),
            progress("li-pod", "conn-b1", time: 42, episode: "ep-1"),
        ]
        snapshot.sessions = [
            LegacySession(id: "session-local", userId: "user-1", libraryItemId: "li-audio", localLibraryItemId: "local_li-audio", mediaType: "book", displayTitle: "Title li-audio", duration: 200, playMethod: 3, startedAt: 1_759_300_000_000, updatedAt: 1_759_300_120_000, timeListening: 120, currentTime: 123.5, serverConnectionConfigId: "conn-a1", serverAddress: "https://books.example.test/abs", isActiveSession: false),
            LegacySession(id: "session-stream", userId: "user-2", libraryItemId: "li-stream", localLibraryItemId: nil, mediaType: "book", duration: 900, playMethod: 0, startedAt: 1_759_300_000_000, updatedAt: 1_759_300_035_000, timeListening: 35, currentTime: 400, serverConnectionConfigId: "conn-a2", serverAddress: "https://books.example.test/abs", isActiveSession: true),
            LegacySession(id: "session-mismatch", userId: "user-1", libraryItemId: "li-x", localLibraryItemId: nil, mediaType: "book", duration: 10, playMethod: 0, startedAt: nil, updatedAt: nil, timeListening: 5, currentTime: 5, serverConnectionConfigId: "conn-a2", serverAddress: "https://books.example.test/abs", isActiveSession: false),
        ]
    }
}

struct FixtureSecrets: LegacySecretSource {
    func secret(for connection: LegacyConnection) throws -> LegacyAccountSecret? {
        guard connection.id != "conn-b1" else { return nil }
        let suffix = connection.id.replacingOccurrences(of: "conn-", with: "")
        return LegacyAccountSecret(accessToken: "\(LegacyFixture.accessMarker)-\(suffix)", refreshToken: "\(LegacyFixture.refreshMarker)-\(suffix)")
    }
}

final class RecordingSecretSink: MigrationSecretSink {
    private(set) var adopted: [(account: MigratedAccount, secret: LegacyAccountSecret)] = []

    func adopt(_ secret: LegacyAccountSecret, for account: MigratedAccount) throws {
        adopted.append((account, secret))
    }
}

/// Real file system with deterministic interruption and capacity control.
final class FaultInjectingFileSystem: MigrationFileSystem {
    private let real = LocalMigrationFileSystem()
    var failAfterTransfers: Int?
    var failCommitWrites = false
    var linksUnavailable = false
    var capacity: Int64?
    private(set) var transfers: [URL] = []
    /// Runs once, right after the first chunk of the named file has been read.
    var afterFirstRead: (name: String, action: (URL) throws -> Void)?

    struct Interrupted: Error {}

    private func transfer(_ source: URL, _ operation: () throws -> Void) throws {
        if let limit = failAfterTransfers, transfers.count >= limit { throw Interrupted() }
        try operation()
        transfers.append(source)
    }

    func link(_ source: URL, to destination: URL) throws {
        if linksUnavailable { throw CocoaError(.fileWriteUnknown) }
        try transfer(source) { try real.link(source, to: destination) }
    }

    func copy(_ source: URL, to destination: URL) throws {
        try transfer(source) { try real.copy(source, to: destination) }
    }

    func availableCapacity(at directory: URL) throws -> Int64 {
        try capacity ?? real.availableCapacity(at: directory)
    }

    func read(_ handle: FileHandle, upToCount count: Int, of url: URL) throws -> Data {
        let chunk = try real.read(handle, upToCount: count, of: url)
        if let hook = afterFirstRead, hook.name == url.lastPathComponent {
            afterFirstRead = nil
            try hook.action(url)
        }
        return chunk
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if failCommitWrites && url.lastPathComponent == "outcome.json" { throw Interrupted() }
        try real.writeAtomically(data, to: url)
    }
}
