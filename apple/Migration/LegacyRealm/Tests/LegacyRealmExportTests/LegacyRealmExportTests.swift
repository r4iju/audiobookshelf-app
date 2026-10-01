import CryptoKit
import Foundation
import LegacyMigration
@testable import LegacyRealmExport
import RealmSwift
import XCTest

/// Builds a synthetic legacy installation the way the schema-21 app lays it out: `Documents/
/// default.realm` beside `Documents/<libraryItemId>/<file>` downloads, Capacitor preferences in
/// UserDefaults and refresh tokens behind a Keychain-shaped reader. All values are invented.
final class LegacyRealmExportTests: XCTestCase {
    private static let accessToken = "SYNTHETIC-REALM-ACCESS-TOKEN"
    private static let refreshToken = "SYNTHETIC-KEYCHAIN-REFRESH-TOKEN"

    private var directory: URL!
    private var documents: URL!
    private var realmURL: URL { documents.appendingPathComponent("default.realm") }
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-realm-\(UUID().uuidString)").resolvingSymlinksInPath()
        documents = directory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        suite = "legacy-realm-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ path: String, _ contents: String) throws -> Int {
        let url = documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return contents.utf8.count
    }

    private func digest() throws -> [String: String] {
        var result: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: documents, includingPropertiesForKeys: nil)! {
            let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            result[url.resolvingSymlinksInPath().path] = type == .typeRegular
                ? SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
                : type?.rawValue ?? "unknown"
        }
        return result
    }

    /// Writes a schema-21 legacy Realm with the full model graph the legacy app persists.
    private func seedLegacyRealm(schemaVersion: UInt64 = 21) throws {
        let mp3Size = try write("li-book/01.mp3", "legacy-audio")
        let pdfSize = try write("li-book/companion.pdf", "%PDF-legacy")
        _ = try write("li-book/cover.jpg", "legacy-cover")
        let episodeSize = try write("li-pod/ep.mp3", "legacy-episode")
        let partSize = try write("li-next/01.mp3", "finished-part")

        let configuration = Realm.Configuration(fileURL: realmURL, schemaVersion: schemaVersion, objectTypes: LegacyRealmSchema.objectTypes)
        try autoreleasepool {
            let realm = try Realm(configuration: configuration)
            try realm.write {
                let server = LegacyRealmServerConnectionConfig()
                server.id = "conn-1"
                server.index = 1
                server.name = "Home"
                server.address = "https://books.example.test/abs"
                server.version = "2.30.0"
                server.userId = "user-1"
                server.username = "alice"
                server.token = Self.accessToken
                realm.add(server)
                let active = LegacyRealmServerConnectionConfigActiveIndex()
                active.index = 1
                realm.add(active)

                let device = LegacyRealmDeviceSettings()
                device.jumpForwardTime = 45
                device.lockOrientation = "LANDSCAPE"
                device.languageCode = "fr"
                realm.add(device)
                let player = LegacyRealmPlayerSettings()
                player.playbackRate = 1.75
                player.chapterTrack = false
                realm.add(player)

                let log = LegacyRealmLogEntry()
                log.message = "synthetic log line"
                realm.add(log)

                func localFile(_ item: String, _ name: String, _ mime: String, _ size: Int) -> LegacyRealmLocalFile {
                    let file = LegacyRealmLocalFile()
                    file.id = "\(item)_\(Data(name.utf8).base64EncodedString())"
                    file.filename = name
                    file._contentUrl = "\(item)/\(name)"
                    file.mimeType = mime
                    file.size = size
                    return file
                }
                let mp3 = localFile("li-book", "01.mp3", "audio/mpeg", mp3Size)
                let pdf = localFile("li-book", "companion.pdf", "application/pdf", pdfSize)
                let book = LegacyRealmLocalLibraryItem()
                book.id = "local_book"
                book._contentUrl = "li-book"
                book.mediaType = "book"
                book.libraryItemId = "li-book"
                book.serverConnectionConfigId = "conn-1"
                book.serverAddress = "https://books.example.test/abs"
                book.serverUserId = "user-1"
                book._coverContentUrl = "li-book/cover.jpg"
                book.localFiles.append(objectsIn: [mp3, pdf])
                let media = LegacyRealmMediaType()
                let metadata = LegacyRealmMetadata()
                metadata.title = "Legacy Book"
                metadata.authorName = "Legacy Author"
                metadata.subtitle = "A Subtitle"
                metadata.narrators.append("Legacy Narrator")
                metadata.seriesName = "Legacy Series #2"
                metadata.desc = "Legacy description"
                metadata.genres.append("Fiction")
                let author = LegacyRealmAuthor()
                author.id = "author-1"
                author.name = "Legacy Author"
                metadata.authors.append(author)
                media.metadata = metadata
                media.tags.append("favourite")
                media.duration = 321
                book.isInvalid = true
                let track = LegacyRealmAudioTrack()
                track.index = 1
                track.startOffset = 0
                track.duration = 321
                track.title = "01.mp3"
                track.mimeType = "audio/mpeg"
                track.localFileId = mp3.id
                media.tracks.append(track)
                let chapter = LegacyRealmChapter()
                chapter.id = 0
                chapter.end = 321
                chapter.title = "Only Chapter"
                media.chapters.append(chapter)
                let ebook = LegacyRealmEBookFile()
                ebook.ino = "ino-pdf"
                ebook.ebookFormat = "pdf"
                ebook.localFileId = pdf.id
                let ebookMetadata = LegacyRealmFileMetadata()
                ebookMetadata.filename = "companion.pdf"
                ebook.metadata = ebookMetadata
                media.ebookFile = ebook
                book.media = media
                realm.add(book)

                let episodeFile = localFile("li-pod", "ep.mp3", "audio/mpeg", episodeSize)
                let podcast = LegacyRealmLocalLibraryItem()
                podcast.id = "local_pod"
                podcast.mediaType = "podcast"
                podcast.libraryItemId = "li-pod"
                podcast.serverConnectionConfigId = "conn-1"
                podcast.serverAddress = "https://books.example.test/abs"
                podcast.serverUserId = "user-1"
                podcast.localFiles.append(episodeFile)
                let podcastMedia = LegacyRealmMediaType()
                let podcastMetadata = LegacyRealmMetadata()
                podcastMetadata.title = "Legacy Podcast"
                podcastMetadata.author = "Legacy Host"
                podcastMedia.metadata = podcastMetadata
                let episode = LegacyRealmPodcastEpisode()
                episode.id = "ep-7"
                episode.title = "Episode Seven"
                episode.duration = 90
                episode.index = 7
                episode.episode = "7"
                episode.episodeType = "full"
                episode.desc = "Episode description"
                episode.size = 1234
                let episodeTrack = LegacyRealmAudioTrack()
                episodeTrack.duration = 90
                episodeTrack.mimeType = "audio/mpeg"
                episodeTrack.localFileId = episodeFile.id
                episode.audioTrack = episodeTrack
                podcastMedia.episodes.append(episode)
                podcast.media = podcastMedia
                realm.add(podcast)

                let bookProgress = LegacyRealmLocalMediaProgress()
                bookProgress.id = "local_book"
                bookProgress.localLibraryItemId = "local_book"
                bookProgress.libraryItemId = "li-book"
                bookProgress.serverConnectionConfigId = "conn-1"
                bookProgress.serverAddress = "https://books.example.test/abs"
                bookProgress.serverUserId = "user-1"
                bookProgress.duration = 321
                bookProgress.currentTime = 200.25
                bookProgress.progress = 200.25 / 321
                bookProgress.ebookLocation = "9"
                bookProgress.ebookProgress = 0.4
                bookProgress.lastUpdate = 1_759_300_000_000
                bookProgress.startedAt = 1_759_000_000_000
                realm.add(bookProgress)
                let episodeProgress = LegacyRealmLocalMediaProgress()
                episodeProgress.id = "local_pod-ep-7"
                episodeProgress.localLibraryItemId = "local_pod"
                episodeProgress.localEpisodeId = "ep-7"
                episodeProgress.libraryItemId = "li-pod"
                episodeProgress.episodeId = "ep-7"
                episodeProgress.serverConnectionConfigId = "conn-1"
                episodeProgress.serverAddress = "https://books.example.test/abs"
                episodeProgress.serverUserId = "user-1"
                episodeProgress.duration = 90
                episodeProgress.currentTime = 30
                episodeProgress.isFinished = false
                episodeProgress.lastUpdate = 1_759_300_000_000
                realm.add(episodeProgress)

                let session = LegacyRealmPlaybackSession()
                session.id = "legacy-session-1"
                session.userId = "user-1"
                session.libraryItemId = "li-book"
                session.mediaType = "book"
                session.displayTitle = "Legacy Book"
                session.duration = 321
                session.playMethod = 3
                session.startedAt = 1_759_300_000_000
                session.updatedAt = 1_759_300_090_000
                session.timeListening = 90
                session.currentTime = 200.25
                session.localLibraryItem = book
                session.serverConnectionConfigId = "conn-1"
                session.serverAddress = "https://books.example.test/abs"
                session.isActiveSession = false
                session.serverUpdatedAt = 1_759_300_000_000
                session.coverPath = "li-book/cover.jpg"
                let sessionChapter = LegacyRealmChapter()
                sessionChapter.id = 0
                sessionChapter.end = 321
                sessionChapter.title = "Only Chapter"
                session.chapters.append(sessionChapter)
                let sessionMetadata = LegacyRealmMetadata()
                sessionMetadata.title = "Legacy Book"
                sessionMetadata.narratorName = "Legacy Narrator"
                session.mediaMetadata = sessionMetadata
                realm.add(session)

                let download = LegacyRealmDownloadItem()
                download.id = "download-1"
                download.libraryItemId = "li-next"
                download.itemTitle = "Unfinished Download"
                download.serverConnectionConfigId = "conn-1"
                download.serverAddress = "https://books.example.test/abs"
                download.serverUserId = "user-1"
                for index in 0..<3 {
                    let part = LegacyRealmDownloadItemPart()
                    part.id = "part-\(index)"
                    part.downloadItemId = "download-1"
                    part.completed = index == 0
                    part.moved = index == 0
                    part.filename = "0\(index + 1).mp3"
                    part.destinationUri = "li-next/0\(index + 1).mp3"
                    part.fileSize = Double(index == 0 ? partSize : 1000)
                    part.uri = "https://books.example.test/abs/api/items/li-next/file/\(index)?token=\(Self.accessToken)"
                    let partTrack = LegacyRealmAudioTrack()
                    partTrack.index = index + 1
                    partTrack.mimeType = "audio/mpeg"
                    part.audioTrack = partTrack
                    download.downloadItemParts.append(part)
                }
                realm.add(download)
            }
            realm.invalidate()
        }
    }

    private func installationSource() throws -> LegacySource {
        try LegacyInstallation.source(documents: documents, defaults: defaults, webStorage: [
            "ereaderSettings": #"{"theme":"dark"}"#,
            "refresh_token_conn-1": Self.refreshToken,
        ], refreshTokens: FakeRefreshTokens(), workDirectory: directory.appendingPathComponent("Work"))
    }

    func testReadsTheSchema21RealmFromACopyAndLeavesTheOriginalUntouched() throws {
        try seedLegacyRealm()
        let before = try digest()

        let contents = try LegacyRealmReader.read(realmAt: realmURL, workDirectory: directory.appendingPathComponent("Work"))

        XCTAssertEqual(try digest(), before, "reading must not modify or add files next to the legacy Realm")
        let snapshot = contents.snapshot
        XCTAssertEqual(snapshot.schemaVersion, 21)
        XCTAssertEqual(snapshot.connections, [LegacyConnection(id: "conn-1", index: 1, name: "Home", address: "https://books.example.test/abs", version: "2.30.0", userId: "user-1", username: "alice")])
        XCTAssertEqual(snapshot.activeConnectionIndex, 1)
        XCTAssertEqual(contents.secrets["conn-1"]?.accessToken, Self.accessToken)
        XCTAssertEqual(snapshot.deviceSettings?.jumpForwardTime, 45)
        XCTAssertEqual(snapshot.deviceSettings?.lockOrientation, "LANDSCAPE")
        XCTAssertEqual(snapshot.deviceSettings?.languageCode, "fr")
        XCTAssertEqual(snapshot.playerSettings, LegacyPlayerSettings(playbackRate: 1.75, chapterTrack: false))

        let book = try XCTUnwrap(snapshot.localItems.first { $0.libraryItemId == "li-book" })
        XCTAssertEqual(book.title, "Legacy Book")
        XCTAssertEqual(book.author, "Legacy Author")
        XCTAssertEqual(book.coverPath, "li-book/cover.jpg")
        XCTAssertEqual(book.files.map(\.path), ["li-book/01.mp3", "li-book/companion.pdf"])
        XCTAssertEqual(book.tracks.first?.localFileId, book.files.first?.id)
        XCTAssertEqual(book.tracks.first?.duration, 321)
        XCTAssertEqual(book.chapters.first?.title, "Only Chapter")
        XCTAssertEqual(book.ebook, LegacyEbook(ino: "ino-pdf", format: "pdf", localFileId: book.files[1].id, filename: "companion.pdf"))
        let podcast = try XCTUnwrap(snapshot.localItems.first { $0.libraryItemId == "li-pod" })
        XCTAssertEqual(podcast.author, "Legacy Host")
        XCTAssertEqual(podcast.episodes.map(\.id), ["ep-7"])
        XCTAssertEqual(podcast.episodes.first?.track?.localFileId, podcast.files.first?.id)

        XCTAssertEqual(snapshot.progress.first { $0.libraryItemId == "li-book" }?.ebookLocation, "9")
        XCTAssertEqual(snapshot.progress.first { $0.libraryItemId == "li-book" }?.currentTime, 200.25)
        XCTAssertEqual(snapshot.progress.first { $0.episodeId == "ep-7" }?.currentTime, 30)
        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertEqual(session.localLibraryItemId, "local_book")
        XCTAssertEqual(session.timeListening, 90)
        XCTAssertFalse(session.isActiveSession)
        XCTAssertEqual(snapshot.pendingDownloads, [LegacyPendingDownload(id: "download-1", libraryItemId: "li-next", episodeId: nil, title: "Unfinished Download", serverConnectionConfigId: "conn-1", serverAddress: "https://books.example.test/abs", serverUserId: "user-1", completedParts: 1, totalParts: 3)])

        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains(Self.accessToken))
        let work = directory.appendingPathComponent("Work")
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: work.path))?.isEmpty ?? true, "the token-bearing Realm copy must be removed after reading")
    }

    func testACredentialCopyLeftByAnInterruptedReadIsRemovedOnTheNextRead() throws {
        try seedLegacyRealm()
        let work = directory.appendingPathComponent("Work")
        let stale = work.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: realmURL, to: stale.appendingPathComponent("legacy.realm"))

        _ = try LegacyRealmReader.read(realmAt: realmURL, workDirectory: work)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testEveryPreservedLegacyFieldIsReadButNeverTheTokenizedDownloadURL() throws {
        try seedLegacyRealm()

        let snapshot = try LegacyRealmReader.read(realmAt: realmURL, workDirectory: directory.appendingPathComponent("Work")).snapshot

        let book = try XCTUnwrap(snapshot.localItems.first { $0.id == "local_book" })
        XCTAssertTrue(book.isInvalid)
        XCTAssertEqual(book.basePath, "")
        XCTAssertEqual(book.metadata?.subtitle, "A Subtitle")
        XCTAssertEqual(book.metadata?.narrators, ["Legacy Narrator"])
        XCTAssertEqual(book.metadata?.seriesName, "Legacy Series #2")
        XCTAssertEqual(book.metadata?.description, "Legacy description")
        XCTAssertEqual(book.metadata?.genres, ["Fiction"])
        XCTAssertEqual(book.metadata?.authors, [LegacyAuthor(id: "author-1", name: "Legacy Author")])
        XCTAssertEqual(book.tags, ["favourite"])
        XCTAssertEqual(book.mediaDuration, 321)
        let episode = try XCTUnwrap(snapshot.localItems.first { $0.id == "local_pod" }?.episodes.first)
        XCTAssertEqual(episode.index, 7)
        XCTAssertEqual(episode.episode, "7")
        XCTAssertEqual(episode.episodeType, "full")
        XCTAssertEqual(episode.description, "Episode description")
        XCTAssertEqual(episode.size, 1234)
        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertEqual(session.chapters.map(\.title), ["Only Chapter"])
        XCTAssertEqual(session.mediaMetadata?.narratorName, "Legacy Narrator")
        XCTAssertEqual(session.coverPath, "li-book/cover.jpg")
        let download = try XCTUnwrap(snapshot.pendingDownloads.first)
        XCTAssertEqual(download.parts.map(\.path), ["li-next/01.mp3", "li-next/02.mp3", "li-next/03.mp3"])
        XCTAssertEqual(download.parts.map(\.moved), [true, false, false])
        XCTAssertEqual(download.parts.first?.role, .track)
        XCTAssertEqual(download.parts.first?.trackIndex, 1)
        XCTAssertEqual(download.parts.first?.size, 13)

        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains(Self.accessToken), "the part download URL carries the access token and must not be read")
    }

    func testANewerLegacySchemaIsRefusedAndKept() throws {
        try seedLegacyRealm(schemaVersion: 22)
        let before = try digest()

        XCTAssertThrowsError(try LegacyRealmReader.read(realmAt: realmURL, workDirectory: directory.appendingPathComponent("Work"))) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .unsupportedLegacySchema(22))
        }
        XCTAssertEqual(try digest(), before)
    }

    func testAnUnreadableLegacyDatabaseIsReportedAndKept() throws {
        try Data("not a realm file".utf8).write(to: realmURL)
        let before = try digest()

        XCTAssertThrowsError(try LegacyRealmReader.read(realmAt: realmURL, workDirectory: directory.appendingPathComponent("Work"))) { error in
            guard case .legacyDatabaseUnreadable? = error as? LegacyMigrationError else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(try digest(), before)
    }

    func testInPlaceUpgradeMigratesTheLegacyInstallation() throws {
        try seedLegacyRealm()
        defaults.set(#"{"playbackRate":1.75}"#, forKey: "CapacitorStorage.playerSettings")
        defaults.set("dark", forKey: "CapacitorStorage.theme")
        defaults.set("lib-books", forKey: "CapacitorStorage.lastLibraryId")
        defaults.set("not-a-legacy-preference", forKey: "CapacitorStorage.somethingElse")
        let before = try digest()

        let source = try installationSource()
        XCTAssertEqual(source.kind, .inPlace)
        let root = directory.appendingPathComponent("NativeContainer/LegacyMigration")
        let migrator = LegacyMigrator(root: root)
        let sink = CapturingSink()
        let outcome = try migrator.migrate(source, secrets: sink)

        XCTAssertEqual(try digest(), before)
        XCTAssertEqual(outcome.accounts.map(\.credentials), [.adopted])
        XCTAssertEqual(sink.secrets.first?.accessToken, Self.accessToken)
        XCTAssertEqual(sink.secrets.first?.refreshToken, Self.refreshToken)
        XCTAssertEqual(outcome.settings.preferences, ["playerSettings": #"{"playbackRate":1.75}"#, "theme": "dark", "lastLibraryId": "lib-books"])
        XCTAssertEqual(outcome.settings.webStorage, ["ereaderSettings": #"{"theme":"dark"}"#])
        let book = try XCTUnwrap(outcome.downloads.first { $0.libraryItemID == "li-book" })
        XCTAssertTrue(book.complete)
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.tracks.first?.file))), Data("legacy-audio".utf8))
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.ebook?.file))), Data("%PDF-legacy".utf8))
        XCTAssertEqual(outcome.progress.first { $0.libraryItemID == "li-book" }?.reading?.page, 9)
        XCTAssertEqual(outcome.pendingSessions.first?.semantics, .sessionTotal)
        XCTAssertEqual(outcome.issues.map(\.code), [.downloadInterrupted])

        for case let url as URL in FileManager.default.enumerator(at: directory.appendingPathComponent("NativeContainer"), includingPropertiesForKeys: nil)! {
            guard let data = try? Data(contentsOf: url) else { continue }
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SYNTHETIC-"), "credential persisted in \(url.lastPathComponent)")
        }
    }

    func testLegacyExportArchiveImportsIntoASeparatelyIdentifiedApp() throws {
        try seedLegacyRealm()
        defaults.set("dark", forKey: "CapacitorStorage.theme")
        let copy = directory.appendingPathComponent("export-copy.realm")
        try FileManager.default.copyItem(at: realmURL, to: copy)
        let before = try digest()

        let archive = try LegacyArchiveExporter.export(documents: documents, realmCopy: copy, defaults: defaults,
                                                       webStorage: ["ereaderSettings": "{}", "device": #"{"token":"\#(Self.accessToken)"}"#],
                                                       workDirectory: directory.appendingPathComponent("Work"),
                                                       to: directory.appendingPathComponent("Export/Audiobookshelf.abslegacy"))
        XCTAssertEqual(try digest(), before)
        for case let url as URL in FileManager.default.enumerator(at: archive, includingPropertiesForKeys: nil)! {
            guard let data = try? Data(contentsOf: url) else { continue }
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SYNTHETIC-"), "credential exported in \(url.lastPathComponent)")
        }

        let migrator = LegacyMigrator(root: directory.appendingPathComponent("PreviewContainer/LegacyMigration"))
        let outcome = try migrator.migrate(try LegacyArchive.open(archive), secrets: CapturingSink())

        XCTAssertEqual(outcome.sourceKind, .archive)
        XCTAssertEqual(outcome.accounts.map(\.credentials), [.reauthenticationRequired])
        XCTAssertEqual(outcome.settings.preferences, ["theme": "dark"])
        XCTAssertEqual(outcome.settings.webStorage, ["ereaderSettings": "{}"])
        let podcast = try XCTUnwrap(outcome.downloads.first { $0.libraryItemID == "li-pod" })
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(podcast.episodes.first?.track?.file))), Data("legacy-episode".utf8))
        XCTAssertEqual(outcome.progress.first { $0.episodeID == "ep-7" }?.currentTime, 30)
    }
}

private struct FakeRefreshTokens: LegacyRefreshTokenReading {
    func refreshToken(forConnectionID id: String) -> String? {
        id == "conn-1" ? "SYNTHETIC-KEYCHAIN-REFRESH-TOKEN" : nil
    }
}

private final class CapturingSink: MigrationSecretSink {
    var secrets: [LegacyAccountSecret] = []
    func adopt(_ secret: LegacyAccountSecret, for account: MigratedAccount) throws {
        secrets.append(secret)
    }
}
