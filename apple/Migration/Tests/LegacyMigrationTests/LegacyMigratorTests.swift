import Foundation
import LegacyMigration
import XCTest

final class LegacyMigratorTests: XCTestCase {
    private var fixture: LegacyFixture!

    override func setUpWithError() throws {
        fixture = try LegacyFixture()
    }

    override func tearDown() {
        fixture.cleanUp()
    }

    private func account(_ server: String, _ user: String) -> MigrationAccount {
        MigrationAccount(address: server, userID: user)!
    }

    private var homeAlice: MigrationAccount { account("https://books.example.test/abs", "user-1") }
    private var homeBob: MigrationAccount { account("https://books.example.test/abs", "user-2") }
    private var lanAlice: MigrationAccount { account("http://192.168.0.20:13378", "user-1") }
    private var oldServer: MigrationAccount { account("https://old.example.test", "user-9") }

    private func download(_ outcome: MigrationOutcome, _ item: String) throws -> MigratedDownload {
        try XCTUnwrap(outcome.downloads.first { $0.libraryItemID == item }, "missing download \(item)")
    }

    private func contents(_ migrator: LegacyMigrator, _ file: MigratedFile?) throws -> String {
        let file = try XCTUnwrap(file)
        return String(decoding: try Data(contentsOf: migrator.fileURL(for: file)), as: UTF8.self)
    }

    private func issues(_ outcome: MigrationOutcome, _ code: MigrationIssue.Code) -> [MigrationIssue] {
        outcome.issues.filter { $0.code == code }
    }

    // MARK: In-place upgrade

    func testInPlaceUpgradeAdoptsAccountsCredentialsSettingsDownloadsProgressAndPendingListening() throws {
        let before = try fixture.legacyTreeDigest()
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let sink = RecordingSecretSink()

        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: sink)

        XCTAssertEqual(try fixture.legacyTreeDigest(), before, "legacy Documents must be byte-identical after migration")
        XCTAssertEqual(outcome.sourceKind, .inPlace)
        XCTAssertEqual(outcome.legacySchemaVersion, 21)

        // Accounts: duplicate configs for the same canonical server user merge; an account known
        // only from downloaded data is kept and needs sign-in.
        XCTAssertEqual(outcome.accounts.map(\.account), [homeAlice, homeBob, lanAlice, oldServer].sorted())
        let alice = try XCTUnwrap(outcome.accounts.first { $0.account == homeAlice })
        XCTAssertEqual(Set(alice.legacyConnectionIDs), ["conn-a1", "conn-a1-dup"])
        XCTAssertEqual(alice.username, "alice")
        XCTAssertEqual(alice.credentials, .adopted)
        XCTAssertTrue(try XCTUnwrap(outcome.accounts.first { $0.account == homeBob }).wasActive)
        XCTAssertEqual(outcome.accounts.first { $0.account == lanAlice }?.credentials, .reauthenticationRequired)
        XCTAssertEqual(outcome.accounts.first { $0.account == oldServer }?.credentials, .reauthenticationRequired)
        XCTAssertEqual(Set(issues(outcome, .reauthenticationRequired).compactMap(\.account)), [lanAlice, oldServer])
        XCTAssertEqual(Set(sink.adopted.map(\.account.account)), [homeAlice, homeBob])
        XCTAssertEqual(sink.adopted.first { $0.account.account == homeBob }?.secret.refreshToken, "\(LegacyFixture.refreshMarker)-a2")

        // Settings survive with their legacy values.
        XCTAssertEqual(outcome.settings.device?.jumpForwardTime, 30)
        XCTAssertEqual(outcome.settings.device?.lockOrientation, "PORTRAIT")
        XCTAssertEqual(outcome.settings.device?.hapticFeedback, "HEAVY")
        XCTAssertEqual(outcome.settings.device?.downloadUsingCellular, "NEVER")
        XCTAssertEqual(outcome.settings.player, LegacyPlayerSettings(playbackRate: 1.35, chapterTrack: false))
        XCTAssertEqual(outcome.settings.preferences["theme"], "black")
        XCTAssertEqual(outcome.settings.preferences["lastLibraryId"], "lib-books")
        XCTAssertNil(outcome.settings.preferences["unrelatedPlugin"])

        // Downloads are adopted without redownloading: same bytes, scoped to their account.
        let audio = try download(outcome, "li-audio")
        XCTAssertEqual(audio.account, homeAlice)
        XCTAssertTrue(audio.complete)
        XCTAssertEqual(audio.tracks.map(\.index), [1, 2])
        XCTAssertEqual(audio.tracks.map(\.startOffset), [0, 100])
        XCTAssertEqual(try contents(migrator, audio.tracks[0].file), "audio-track-one")
        XCTAssertEqual(try contents(migrator, audio.tracks[1].file), "audio-track-two-longer")
        XCTAssertEqual(try contents(migrator, audio.cover), "cover-bytes")
        XCTAssertEqual(audio.chapters.map(\.title), ["Chapter 1"])

        let podcast = try download(outcome, "li-pod")
        XCTAssertEqual(podcast.account, lanAlice)
        XCTAssertEqual(podcast.episodes.map(\.id), ["ep-1"])
        XCTAssertEqual(try contents(migrator, podcast.episodes.first?.track?.file), "episode-audio")

        // Listening progress keeps its position and account.
        let audioProgress = try XCTUnwrap(outcome.progress.first { $0.libraryItemID == "li-audio" })
        XCTAssertEqual(audioProgress.account, homeAlice)
        XCTAssertEqual(audioProgress.currentTime, 123.5)
        XCTAssertEqual(audioProgress.lastUpdate, 1_759_300_000_000)
        let episodeProgress = try XCTUnwrap(outcome.progress.first { $0.episodeID == "ep-1" })
        XCTAssertEqual(episodeProgress.account, lanAlice)
        XCTAssertEqual(episodeProgress.currentTime, 42)

        // Unsent listening is retained with the semantics needed to report it exactly once.
        let local = try XCTUnwrap(outcome.pendingSessions.first { $0.session.id == "session-local" })
        XCTAssertEqual(local.account, homeAlice)
        XCTAssertEqual(local.semantics, .sessionTotal)
        XCTAssertEqual(local.session.timeListening, 120)
        let stream = try XCTUnwrap(outcome.pendingSessions.first { $0.session.id == "session-stream" })
        XCTAssertEqual(stream.account, homeBob)
        XCTAssertEqual(stream.semantics, .sinceLastSync)
        XCTAssertEqual(stream.session.timeListening, 35)

        XCTAssertEqual(try migrator.committedOutcome(), outcome)
    }

    func testReaderFilesAssociationsLocationsAndSettingsArePreservedForEveryBaselineFormat() throws {
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let expected: [(item: String, format: String, bytes: String, kind: MigratedReadingLocation.Kind, raw: String, page: Int?)] = [
            ("li-pdf", "pdf", "%PDF-1.7 synthetic", .page, "12", 12),
            ("li-epub", "epub", "PK-epub-synthetic", .cfi, "epubcfi(/6/14!/4/2/1:0)", nil),
            ("li-mobi", "mobi", "BOOKMOBI-synthetic", .opaque, "loc-1520", nil),
            ("li-azw3", "azw3", "AZW3-synthetic", .opaque, "kindle-pos:88", nil),
            ("li-cbz", "cbz", "PK-cbz-synthetic", .page, "7", 7),
            ("li-cbr", "cbr", "Rar!-cbr-synthetic", .page, "3", 3),
            ("li-pdf-bad", "pdf", "%PDF-1.4 synthetic", .invalid, "chapter-3", nil),
        ]
        for entry in expected {
            let item = try download(outcome, entry.item)
            XCTAssertEqual(item.ebook?.format, entry.format, entry.item)
            XCTAssertEqual(item.ebook?.ino, "ino-\(entry.item)", entry.item)
            XCTAssertEqual(try contents(migrator, item.ebook?.file), entry.bytes, entry.item)
            let reading = try XCTUnwrap(outcome.progress.first { $0.libraryItemID == entry.item }?.reading, entry.item)
            XCTAssertEqual(reading.format, entry.format, entry.item)
            XCTAssertEqual(reading.kind, entry.kind, entry.item)
            XCTAssertEqual(reading.raw, entry.raw, entry.item)
            XCTAssertEqual(reading.page, entry.page, entry.item)
        }
        XCTAssertEqual(outcome.progress.first { $0.libraryItemID == "li-pdf" }?.account, homeBob)
        XCTAssertEqual(outcome.progress.first { $0.libraryItemID == "li-pdf" }?.reading?.fraction, 0.3)
        XCTAssertEqual(issues(outcome, .invalidReadingLocation).map(\.libraryItemID), ["li-pdf-bad"])

        XCTAssertEqual(outcome.settings.webStorage["ereaderSettings"], fixture.snapshot.webStorage["ereaderSettings"])
        XCTAssertEqual(outcome.settings.webStorage["ebookLocations-li-epub"], fixture.snapshot.webStorage["ebookLocations-li-epub"])
        XCTAssertEqual(outcome.settings.webStorage["absDeviceId"], "legacy-device-1")
    }

    func testCredentialsOnlyCrossThroughTheSecretSink() throws {
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertNil(outcome.settings.webStorage["device"])
        XCTAssertNil(outcome.settings.webStorage["refresh_token_conn-a1"])
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains(LegacyFixture.accessMarker), "access token persisted in \(url.lastPathComponent)")
            XCTAssertFalse(text.contains(LegacyFixture.refreshMarker), "refresh token persisted in \(url.lastPathComponent)")
        }
        let secret = try XCTUnwrap(FixtureSecrets().secret(for: fixture.snapshot.connections[0]))
        XCTAssertFalse("\(secret)".contains(LegacyFixture.accessMarker))
        XCTAssertFalse(String(reflecting: secret).contains(LegacyFixture.refreshMarker))
    }

    func testUnresolvedDataIsKeptAndExplained() throws {
        let before = try fixture.legacyTreeDigest()
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let missing = try download(outcome, "li-missing")
        XCTAssertFalse(missing.complete)
        XCTAssertNil(missing.tracks.first?.file)
        XCTAssertEqual(issues(outcome, .fileMissing).map(\.legacyPath), ["li-missing/gone.mp3"])

        let truncated = try download(outcome, "li-trunc")
        XCTAssertFalse(truncated.complete)
        XCTAssertNil(truncated.tracks.first?.file)
        XCTAssertEqual(issues(outcome, .fileIncomplete).map(\.legacyPath), ["li-trunc/part.mp3"])

        let orphan = try download(outcome, "li-orphan")
        XCTAssertNil(orphan.account)
        XCTAssertEqual(try contents(migrator, orphan.tracks.first?.file), "orphan-audio")
        XCTAssertEqual(issues(outcome, .unscopedData).map(\.libraryItemID), ["li-orphan"])

        let removed = try download(outcome, "li-removed")
        XCTAssertEqual(removed.account, oldServer)

        let mismatch = try XCTUnwrap(outcome.pendingSessions.first { $0.session.id == "session-mismatch" })
        XCTAssertNil(mismatch.account, "a session whose user differs from its connection must not be attributed to either account")
        XCTAssertEqual(issues(outcome, .accountMismatch).count, 1)

        for issue in outcome.issues { XCTAssertFalse(issue.message.isEmpty) }
        XCTAssertEqual(try fixture.legacyTreeDigest(), before)
    }

    func testDownloadsInterruptedByTheUpgradeAreReportedForRestart() throws {
        fixture.snapshot.pendingDownloads = [
            LegacyPendingDownload(id: "dl-1", libraryItemId: "li-next", episodeId: nil, title: "Next Book", serverConnectionConfigId: "conn-a2", serverAddress: "https://books.example.test/abs", serverUserId: "user-2", completedParts: 1, totalParts: 3),
        ]
        let outcome = try LegacyMigrator(root: fixture.migrationRoot()).migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let interrupted = issues(outcome, .downloadInterrupted)
        XCTAssertEqual(interrupted.map(\.libraryItemID), ["li-next"])
        XCTAssertEqual(interrupted.first?.account, homeBob)
        XCTAssertTrue(interrupted.first?.message.contains("Next Book") == true)
    }

    func testPreflightReportsPlanWithoutWriting() throws {
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)

        let preflight = try migrator.preflight(fixture.inPlaceSource)

        XCTAssertEqual(preflight.accounts, [homeAlice, homeBob, lanAlice, oldServer].sorted())
        XCTAssertEqual(preflight.adoptableFiles, 13)
        XCTAssertGreaterThan(preflight.requiredBytesIfCopied, 0)
        XCTAssertTrue(preflight.issues.contains { $0.code == .fileMissing })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    // MARK: Retries, interruption and recovery

    func testInterruptedMigrationResumesWithoutRepeatingVerifiedWorkAndCommitsOnce() throws {
        let before = try fixture.legacyTreeDigest()
        let fileSystem = FaultInjectingFileSystem()
        fileSystem.failAfterTransfers = 5
        let migrator = LegacyMigrator(root: fixture.migrationRoot(), fileSystem: fileSystem)

        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()))
        XCTAssertNil(try migrator.committedOutcome(), "an interrupted migration must not look committed")
        XCTAssertEqual(try fixture.legacyTreeDigest(), before)
        let firstAttempt = fileSystem.transfers

        fileSystem.failAfterTransfers = nil
        let resumed = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let repeated = fileSystem.transfers.dropFirst(firstAttempt.count).filter(firstAttempt.contains)
        XCTAssertTrue(repeated.isEmpty, "verified files were transferred again: \(repeated)")

        let reference = try LegacyMigrator(root: fixture.migrationRoot("reference")).migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        XCTAssertEqual(resumed, reference)
        XCTAssertEqual(try contents(migrator, try download(resumed, "li-audio").tracks[1].file), "audio-track-two-longer")
        XCTAssertEqual(try fixture.legacyTreeDigest(), before)
    }

    func testCommitInterruptionLeavesNoPartialOutcomeAndRetrySucceeds() throws {
        let fileSystem = FaultInjectingFileSystem()
        fileSystem.failCommitWrites = true
        let migrator = LegacyMigrator(root: fixture.migrationRoot(), fileSystem: fileSystem)

        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()))
        XCTAssertNil(try migrator.committedOutcome())

        fileSystem.failCommitWrites = false
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        XCTAssertEqual(try migrator.committedOutcome(), outcome)
    }

    func testRepeatingACommittedMigrationIsANoOp() throws {
        let fileSystem = FaultInjectingFileSystem()
        let migrator = LegacyMigrator(root: fixture.migrationRoot(), fileSystem: fileSystem)
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let transfers = fileSystem.transfers.count

        let sink = RecordingSecretSink()
        let second = try migrator.migrate(fixture.inPlaceSource, secrets: sink)

        XCTAssertEqual(second, first)
        XCTAssertEqual(fileSystem.transfers.count, transfers)
        XCTAssertTrue(sink.adopted.isEmpty, "credentials must not be re-adopted over a later sign-in")
    }

    func testCorruptJournalAndTamperedAdoptedFileAreRecoveredWithoutLosingEvidence() throws {
        let root = fixture.migrationRoot()
        let fileSystem = FaultInjectingFileSystem()
        fileSystem.failAfterTransfers = 6
        let migrator = LegacyMigrator(root: root, fileSystem: fileSystem)
        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()))

        let journal = root.appendingPathComponent("state.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        try Data("{ not json".utf8).write(to: journal)
        let adopted = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Files"), includingPropertiesForKeys: nil)
            .flatMap { try FileManager.default.subpathsOfDirectory(atPath: $0.path).map($0.appendingPathComponent) }
            .filter { !$0.hasDirectoryPath && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let tampered = try XCTUnwrap(adopted.first)
        try FileManager.default.removeItem(at: tampered)
        try Data("tampered".utf8).write(to: tampered)

        fileSystem.failAfterTransfers = nil
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let preserved = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("state.corrupt-") }
        XCTAssertEqual(preserved.count, 1, "the unreadable journal is kept for diagnosis")
        let reference = try LegacyMigrator(root: fixture.migrationRoot("reference")).migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        XCTAssertEqual(outcome, reference)
        for download in outcome.downloads {
            for file in download.tracks.compactMap(\.file) + [download.cover, download.ebook?.file].compactMap({ $0 }) {
                let legacy = try Data(contentsOf: fixture.documents.appendingPathComponent(file.legacyPath))
                XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: file)), legacy, file.legacyPath)
            }
        }
    }

    func testUnsupportedSchemaStopsBeforeAnyWrite() throws {
        fixture.snapshot.schemaVersion = 22
        let root = fixture.migrationRoot()
        XCTAssertThrowsError(try LegacyMigrator(root: root).migrate(fixture.inPlaceSource)) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .unsupportedLegacySchema(22))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testADifferentSourceNeverOverwritesACommittedMigration() throws {
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        fixture.snapshot.progress[0].currentTime = 1
        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource)) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .differentSourceAlreadyCommitted)
        }
        XCTAssertEqual(try migrator.committedOutcome(), first)
    }

    func testCopyFallbackChecksFreeSpaceAndIsRetryable() throws {
        let fileSystem = FaultInjectingFileSystem()
        fileSystem.linksUnavailable = true
        fileSystem.capacity = 10
        let migrator = LegacyMigrator(root: fixture.migrationRoot(), fileSystem: fileSystem)

        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())) { error in
            guard case .insufficientSpace(let required, let available)? = error as? LegacyMigrationError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertGreaterThan(required, available)
        }
        XCTAssertTrue(fileSystem.transfers.isEmpty)

        fileSystem.capacity = nil
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        XCTAssertEqual(try contents(migrator, try download(outcome, "li-pdf").ebook?.file), "%PDF-1.7 synthetic")
    }

    // MARK: Export archive across the sandbox boundary

    func testArchiveImportPreservesDataButRequiresSignIn() throws {
        let before = try fixture.legacyTreeDigest()
        let exportDirectory = fixture.directory.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let archive = try LegacyArchive.write(fixture.snapshot, documents: fixture.documents, to: exportDirectory.appendingPathComponent("Audiobookshelf.abslegacy"))
        XCTAssertEqual(try fixture.legacyTreeDigest().filter { !$0.key.hasPrefix("/Exports/") }, before)

        let source = try LegacyArchive.open(archive)
        XCTAssertEqual(source.kind, .archive)
        let sink = RecordingSecretSink()
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let outcome = try migrator.migrate(source, secrets: sink)

        XCTAssertTrue(sink.adopted.isEmpty)
        XCTAssertTrue(outcome.accounts.allSatisfy { $0.credentials == .reauthenticationRequired })
        XCTAssertEqual(Set(issues(outcome, .reauthenticationRequired).compactMap(\.account)), Set(outcome.accounts.map(\.account)))
        XCTAssertEqual(try contents(migrator, try download(outcome, "li-audio").tracks[0].file), "audio-track-one")
        XCTAssertEqual(try contents(migrator, try download(outcome, "li-cbr").ebook?.file), "Rar!-cbr-synthetic")
        XCTAssertEqual(outcome.progress.first { $0.libraryItemID == "li-pdf" }?.reading?.page, 12)
        XCTAssertEqual(outcome.pendingSessions.count, 3)

        let enumerator = FileManager.default.enumerator(at: archive, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator {
            guard let data = try? Data(contentsOf: url) else { continue }
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SYNTHETIC-"), "credential marker in archive \(url.lastPathComponent)")
        }
    }

    func testCorruptArchiveFileIsReportedWhileOtherDataImports() throws {
        let archive = try LegacyArchive.write(fixture.snapshot, documents: fixture.documents, to: fixture.directory.appendingPathComponent("Audiobookshelf.abslegacy"))
        try Data("bit-rot".utf8).write(to: archive.appendingPathComponent("files/li-epub/book.epub"))

        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let outcome = try migrator.migrate(try LegacyArchive.open(archive), secrets: nil)

        let epub = try download(outcome, "li-epub")
        XCTAssertNil(epub.ebook?.file)
        XCTAssertFalse(epub.complete)
        XCTAssertEqual(issues(outcome, .fileCorrupt).map(\.legacyPath), ["li-epub/book.epub"])
        XCTAssertEqual(outcome.progress.first { $0.libraryItemID == "li-epub" }?.reading?.raw, "epubcfi(/6/14!/4/2/1:0)")
        XCTAssertEqual(try contents(migrator, try download(outcome, "li-pdf").ebook?.file), "%PDF-1.7 synthetic")
    }

    func testIncompleteArchiveIsRejected() throws {
        let archive = try LegacyArchive.write(fixture.snapshot, documents: fixture.documents, to: fixture.directory.appendingPathComponent("Audiobookshelf.abslegacy"))
        try FileManager.default.removeItem(at: archive.appendingPathComponent(LegacyArchive.manifestName))

        XCTAssertThrowsError(try LegacyArchive.open(archive)) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .archiveIncomplete)
        }
    }

    func testPathsEscapingTheSourceAreNeverRead() throws {
        let outside = fixture.directory.appendingPathComponent("outside-secret.txt")
        try Data("outside".utf8).write(to: outside)
        fixture.snapshot.localItems[0].files.append(LegacyLocalFile(id: "escape", filename: "outside-secret.txt", path: "../outside-secret.txt", mimeType: "audio/mpeg", size: 7))
        fixture.snapshot.localItems[0].tracks.append(LegacyTrack(index: 3, localFileId: "escape", startOffset: 200, duration: 1, mimeType: "audio/mpeg"))
        fixture.snapshot.localItems[1].coverPath = "/etc/hosts"

        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertEqual(Set(issues(outcome, .unsafePath).compactMap(\.legacyPath)), ["../outside-secret.txt", "/etc/hosts"])
        XCTAssertNil(try download(outcome, "li-audio").tracks.last?.file)
        XCTAssertNil(try download(outcome, "li-pdf").cover)
    }
}
