import CryptoKit
import UIKit
import XCTest

@MainActor final class MemoryCredentials: CredentialStore {
    var value: Credentials?
    func load() throws -> Credentials? { value }
    func save(_ credentials: Credentials) throws { value = credentials }
    func clear() throws { value = nil }
}

/// A synthetic legacy installation exported as an archive (the preview's route), the production
/// migrator, and the production native stores on storage private to one test.
@MainActor final class AdoptionHarness {
    static let server = "https://books.example.test/abs"
    static let alice = MigrationAccount(address: server, userID: "user-1")!
    static let bob = MigrationAccount(address: server, userID: "user-2")!
    static let legacyUpdate = 1_759_300_000_000.0

    let base: URL
    let documents: URL
    var snapshot = LegacySnapshot()
    let migrator: LegacyMigrator
    let stub = StubServer()
    let credentials = MemoryCredentials()
    let defaults: UserDefaults
    private let suite: String
    let session: URLSession
    let api: APIClient
    private(set) var downloads: NativeDownloads!
    private(set) var player: ApplePlayback!
    private(set) var reading: ReadingStore!
    private(set) var adoption: NativeMigrationAdoption!
    private var exports = 0
    private(set) var source: LegacySource?

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("adoption-\(UUID().uuidString)", isDirectory: true)
        documents = base.appendingPathComponent("LegacyDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        migrator = LegacyMigrator(root: base.appendingPathComponent("Native/LegacyMigration", isDirectory: true))
        suite = "adoption-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        session = stub.session()
        api = APIClient(store: credentials, session: session)
        snapshot.connections = [
            LegacyConnection(id: "conn-alice", index: 0, name: "Home", address: Self.server + "/", version: "2.30.0", userId: "user-1", username: "alice"),
            LegacyConnection(id: "conn-bob", index: 1, name: "Home (Bob)", address: Self.server, version: "2.30.0", userId: "user-2", username: "bob"),
        ]
        snapshot.activeConnectionIndex = 0
        openStores()
    }

    func cleanUp() {
        StubProtocol.server = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    var downloadsDirectory: URL { base.appendingPathComponent("Native/NativeDownloads", isDirectory: true) }
    var readingFile: URL { base.appendingPathComponent("Native/NativeListening/reading.json") }
    var adoptionDirectory: URL { base.appendingPathComponent("Native/NativeMigrationAdoption", isDirectory: true) }

    /// Constructs the stores from what is on disk, as a relaunch does.
    func openStores() {
        downloads = NativeDownloads(api: api, directory: downloadsDirectory, configuration: .ephemeral)
        player = ApplePlayback(api: api, progressResets: base.appendingPathComponent("Native/NativeListening/progress-resets.json"))
        reading = ReadingStore(player: player, file: readingFile)
        adoption = NativeMigrationAdoption(downloads: downloads, reading: reading, api: api, defaults: defaults, directory: adoptionDirectory, session: session)
    }

    static func identity(_ account: MigrationAccount) -> AccountIdentity {
        try! AccountIdentity(server: account.server, userID: account.userID)
    }

    func signIn(_ account: MigrationAccount) {
        credentials.value = Credentials(server: account.server, accessToken: "SYNTHETIC-\(account.userID)", refreshToken: nil, userID: account.userID, username: account.userID)
        try! api.restoreSavedCredentials()
    }

    // MARK: Legacy installation

    @discardableResult
    func writeLegacyFile(_ path: String, _ data: Data, mime: String) throws -> LegacyLocalFile {
        let url = documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        let name = (path as NSString).lastPathComponent
        return LegacyLocalFile(id: "\(path.split(separator: "/")[0])_\(Data(name.utf8).base64EncodedString())", filename: name, path: path, mimeType: mime, size: data.count)
    }

    func legacyBytes(_ path: String) throws -> Data { try Data(contentsOf: documents.appendingPathComponent(path)) }

    private func owner(_ account: MigrationAccount?) -> (String?, String?, String?) {
        guard let account else { return (nil, nil, nil) }
        let connection = account == Self.alice ? "conn-alice" : "conn-bob"
        return (connection, Self.server, account.userID)
    }

    /// An audiobook with real WAV tracks of the given lengths. A track listed in `missing` is
    /// recorded by the legacy app but absent from its Documents.
    func addAudiobook(_ id: String, seconds: [Double], account: MigrationAccount? = alice, position: Double? = nil, missing: Set<Int> = [], supplementary: Data? = nil, recordedUser: String? = nil) throws {
        var files: [LegacyLocalFile] = []
        var tracks: [LegacyTrack] = []
        var offset = 0.0
        for (index, length) in seconds.enumerated() {
            let path = "\(id)/\(String(format: "%02d", index + 1)) Part.wav"
            let data = Self.wav(seconds: length, tone: 220 + Double(index) * 110)
            var file: LegacyLocalFile
            if missing.contains(index) {
                let name = (path as NSString).lastPathComponent
                file = LegacyLocalFile(id: "\(id)_\(Data(name.utf8).base64EncodedString())", filename: name, path: path, mimeType: "audio/wav", size: data.count)
                pendingFiles[path] = data
            } else {
                file = try writeLegacyFile(path, data, mime: "audio/wav")
            }
            files.append(file)
            tracks.append(LegacyTrack(index: index + 1, localFileId: file.id, title: file.filename, startOffset: offset, duration: length, mimeType: "audio/wav", contentUrl: "/api/items/\(id)/file/ino-\(id)-\(index + 1)", serverIndex: index))
            offset += length
        }
        if let supplementary {
            files.append(try writeLegacyFile("\(id)/companion.pdf", supplementary, mime: "application/pdf"))
        }
        let (connection, address, user) = owner(account)
        snapshot.localItems.append(LegacyLocalItem(
            id: "local_\(id)", libraryItemId: id, mediaType: "book", serverConnectionConfigId: connection, serverAddress: address, serverUserId: recordedUser ?? user,
            title: "Title \(id)", author: "Author \(id)", files: files, tracks: tracks,
            chapters: [LegacyChapter(id: 0, start: 0, end: offset, title: "Chapter 1")], mediaDuration: offset))
        if let position {
            snapshot.progress.append(LegacyProgress(id: "local_\(id)", localLibraryItemId: "local_\(id)", libraryItemId: id, serverConnectionConfigId: connection, serverAddress: address,
                                                    serverUserId: recordedUser ?? user, duration: offset, progress: position / offset, currentTime: position, lastUpdate: Self.legacyUpdate, startedAt: Self.legacyUpdate - 86_400_000))
        }
    }

    /// Files recorded by the legacy app but absent until `restorePendingFiles`.
    private var pendingFiles: [String: Data] = [:]

    func restorePendingFiles() throws {
        for (path, data) in pendingFiles {
            let url = documents.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        pendingFiles = [:]
    }

    func addEbook(_ id: String, format: String, data: Data, account: MigrationAccount? = alice, location: String?, fraction: Double?) throws {
        let file = try writeLegacyFile("\(id)/book.\(format)", data, mime: format == "pdf" ? "application/pdf" : "application/octet-stream")
        let (connection, address, user) = owner(account)
        snapshot.localItems.append(LegacyLocalItem(
            id: "local_\(id)", libraryItemId: id, mediaType: "book", serverConnectionConfigId: connection, serverAddress: address, serverUserId: user,
            title: "Title \(id)", author: "Author \(id)", files: [file], ebook: LegacyEbook(ino: "ino-\(id)", format: format, localFileId: file.id, filename: file.filename)))
        if let location {
            snapshot.progress.append(LegacyProgress(id: "local_\(id)", localLibraryItemId: "local_\(id)", libraryItemId: id, serverConnectionConfigId: connection, serverAddress: address,
                                                    serverUserId: user, duration: 0, progress: 0, currentTime: 0, ebookLocation: location, ebookProgress: fraction,
                                                    lastUpdate: Self.legacyUpdate, startedAt: Self.legacyUpdate - 86_400_000))
        }
    }

    func addPodcast(_ id: String, episodes: [(id: String, seconds: Double)], account: MigrationAccount? = alice) throws {
        var files: [LegacyLocalFile] = []
        var legacyEpisodes: [LegacyEpisode] = []
        for (index, episode) in episodes.enumerated() {
            let file = try writeLegacyFile("\(id)/\(episode.id).wav", Self.wav(seconds: episode.seconds, tone: 330 + Double(index) * 55), mime: "audio/wav")
            files.append(file)
            legacyEpisodes.append(LegacyEpisode(id: episode.id, title: "Episode \(episode.id)", duration: episode.seconds,
                                                track: LegacyTrack(index: 1, localFileId: file.id, startOffset: 0, duration: episode.seconds, mimeType: "audio/wav", contentUrl: "/api/items/\(id)/file/ino-\(episode.id)", serverIndex: 0)))
        }
        let (connection, address, user) = owner(account)
        snapshot.localItems.append(LegacyLocalItem(
            id: "local_\(id)", libraryItemId: id, mediaType: "podcast", serverConnectionConfigId: connection, serverAddress: address, serverUserId: user,
            title: "Podcast \(id)", author: "Host", files: files, episodes: legacyEpisodes))
    }

    func addSession(_ id: String, item: String, account: MigrationAccount, streamed: Bool, listened: Double, position: Double, updatedAt: Double = legacyUpdate, recordedUser: String? = nil) {
        let (connection, address, user) = owner(account)
        snapshot.sessions.append(LegacySession(
            id: id, userId: recordedUser ?? user, libraryItemId: item, localLibraryItemId: streamed ? nil : "local_\(item)", mediaType: "book", displayTitle: "Title \(item)", displayAuthor: "Author \(item)",
            duration: 900, playMethod: streamed ? 0 : 3, startedAt: updatedAt - 600_000, updatedAt: updatedAt, timeListening: listened, currentTime: position,
            serverConnectionConfigId: connection, serverAddress: address, isActiveSession: false))
    }

    func addProgress(_ item: String, account: MigrationAccount, position: Double, duration: Double, finished: Bool = false, lastUpdate: Double) {
        let (connection, address, user) = owner(account)
        snapshot.progress.append(LegacyProgress(id: "local_\(item)", localLibraryItemId: "local_\(item)", libraryItemId: item, serverConnectionConfigId: connection, serverAddress: address,
                                                serverUserId: user, duration: duration, progress: position / duration, currentTime: position, isFinished: finished,
                                                lastUpdate: lastUpdate, startedAt: lastUpdate - 86_400_000))
    }

    func addInterruptedDownload(_ id: String, finished: [(file: String, seconds: Double)], unfinished: [String], account: MigrationAccount = alice) throws {
        var parts: [LegacyDownloadPart] = []
        for (index, part) in finished.enumerated() {
            let file = try writeLegacyFile("\(id)/\(part.file)", Self.wav(seconds: part.seconds, tone: 500 + Double(index) * 40), mime: "audio/wav")
            parts.append(LegacyDownloadPart(id: "part-\(index)", filename: file.filename, path: file.path, size: file.size, completed: true, moved: true, role: .track, trackIndex: index))
        }
        for (offset, name) in unfinished.enumerated() {
            parts.append(LegacyDownloadPart(id: "part-u\(offset)", filename: name, path: "\(id)/\(name)", size: 0, completed: false, moved: false, role: .track, trackIndex: finished.count + offset))
        }
        let (connection, address, user) = owner(account)
        snapshot.pendingDownloads.append(LegacyPendingDownload(id: "download-\(id)", libraryItemId: id, episodeId: nil, title: "Title \(id)", serverConnectionConfigId: connection,
                                                               serverAddress: address, serverUserId: user, completedParts: finished.count, totalParts: finished.count + unfinished.count,
                                                               mediaType: "book", parts: parts))
    }

    // MARK: Migration

    /// Exports the legacy installation as the legacy app would and opens the archive.
    func export() throws -> LegacySource {
        exports += 1
        let archive = base.appendingPathComponent("Exports/export-\(exports).absmigration")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LegacyArchive.write(snapshot, documents: documents, to: archive)
        let opened = try LegacyArchive.open(archive)
        source = opened
        return opened
    }

    func migrate() throws -> MigrationOutcome {
        try migrator.migrate(source ?? export())
    }

    /// Byte digest of every file of the legacy installation and of every export.
    func originalDigests() throws -> [String: String] {
        var result: [String: String] = [:]
        for directory in [documents, base.appendingPathComponent("Exports")] where FileManager.default.fileExists(atPath: directory.path) {
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                result[url.path] = Self.sha256(try Data(contentsOf: url))
            }
        }
        return result
    }

    // MARK: Native state

    func entry(_ item: String, episode: String? = nil, supplementary: String? = nil) -> NativeDownloads.Entry? {
        downloads.entries.first { $0.media.libraryItemID == item && $0.media.episodeID == episode && $0.supplementaryID == supplementary }
    }

    func entries(_ item: String) -> [NativeDownloads.Entry] {
        downloads.entries.filter { $0.media.libraryItemID == item }
    }

    func localFiles() -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: downloadsDirectory, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: downloadsDirectory.path, with: "") }.sorted()
    }

    // MARK: Media

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// 16-bit mono PCM at 8 kHz.
    static func wav(seconds: Double, tone: Double) -> Data {
        let rate = 8000
        let samples = Int(seconds * Double(rate))
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples * 2).littleEndian)
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16).littleEndian); append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian); append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples * 2).littleEndian)
        for index in 0..<samples {
            append(Int16(sin(Double(index) * 2 * .pi * tone / Double(rate)) * 8000).littleEndian)
        }
        return data
    }

    static func pdf(pages: Int) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            for page in 1...pages {
                context.beginPage()
                ("Page \(page)" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
    }
}
