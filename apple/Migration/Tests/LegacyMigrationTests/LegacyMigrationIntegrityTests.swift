import Foundation
import LegacyMigration
import XCTest

/// Containment, ownership, commit integrity and completeness of the migrated record.
final class LegacyMigrationIntegrityTests: XCTestCase {
    private var fixture: LegacyFixture!

    override func setUpWithError() throws {
        fixture = try LegacyFixture()
    }

    override func tearDown() {
        fixture.cleanUp()
    }

    private var homeAlice: MigrationAccount { MigrationAccount(address: "https://books.example.test/abs", userID: "user-1")! }
    private var homeBob: MigrationAccount { MigrationAccount(address: "https://books.example.test/abs", userID: "user-2")! }

    private func local(_ outcome: MigrationOutcome, _ legacyLocalItemID: String) throws -> MigratedDownload {
        try XCTUnwrap(outcome.downloads.first { $0.legacyLocalItemID == legacyLocalItemID }, "missing download \(legacyLocalItemID)")
    }

    private func contents(_ migrator: LegacyMigrator, _ file: MigratedFile?) throws -> String {
        String(decoding: try Data(contentsOf: migrator.fileURL(for: try XCTUnwrap(file))), as: UTF8.self)
    }

    private func allFiles(_ outcome: MigrationOutcome) -> [MigratedFile] {
        outcome.downloads.flatMap { $0.files.compactMap(\.file) } + outcome.interruptedDownloads.flatMap { $0.parts.compactMap(\.file) }
    }

    private func addItem(id: String, connection: String, path: String, contents: String) throws {
        let file = try fixture.writeFile(path, contents)
        let owner = fixture.snapshot.connections.first { $0.id == connection }!
        fixture.snapshot.localItems.append(LegacyLocalItem(
            id: id, libraryItemId: "li-\(UUID().uuidString)", mediaType: "book", serverConnectionConfigId: connection,
            serverAddress: owner.address, serverUserId: owner.userId, title: "Item \(id)", files: [file],
            tracks: [LegacyTrack(index: 1, localFileId: file.id, startOffset: 0, duration: 10, mimeType: "audio/mpeg")]
        ))
    }

    // MARK: 1. Destination containment and uniqueness

    func testLegacyItemIdentitiesCanNeitherEscapeNorCollideInsideAnAccount() throws {
        try addItem(id: "a/b", connection: "conn-a1", path: "dir-x/track.mp3", contents: "x-audio")
        try addItem(id: "a_b", connection: "conn-a1", path: "dir-y/track.mp3", contents: "y-audio")
        try addItem(id: "..", connection: "conn-a1", path: "dir-z/track.mp3", contents: "z-audio")
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)

        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertEqual(try contents(migrator, try local(outcome, "a/b").tracks.first?.file), "x-audio")
        XCTAssertEqual(try contents(migrator, try local(outcome, "a_b").tracks.first?.file), "y-audio")
        XCTAssertEqual(try contents(migrator, try local(outcome, "..").tracks.first?.file), "z-audio")
        let files = root.appendingPathComponent("Files").standardizedFileURL.path
        let aliceDirectory = try XCTUnwrap(try local(outcome, "local_li-audio").tracks.first?.file?.path.split(separator: "/").first)
        for file in allFiles(outcome) {
            XCTAssertFalse(file.path.split(separator: "/").contains { $0 == ".." || $0 == "." }, file.path)
            XCTAssertTrue(migrator.fileURL(for: file).standardizedFileURL.path.hasPrefix(files + "/"), file.path)
        }
        for id in ["a/b", "a_b", ".."] {
            XCTAssertEqual(try local(outcome, id).tracks.first?.file?.path.split(separator: "/").first, aliceDirectory, id)
        }
        let paths = allFiles(outcome).map(\.path)
        XCTAssertEqual(Set(paths).count, Set(allFiles(outcome).map { "\($0.path)|\($0.sha256)" }).count, "one destination must never hold two different files")
    }

    // MARK: 2. Journal loss cannot unlock the committed outcome

    func testALostOrCorruptJournalCannotLetAnotherSourceReplaceTheCommittedOutcome() throws {
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let outcomeURL = root.appendingPathComponent("outcome.json")
        let committed = try Data(contentsOf: outcomeURL)
        let journal = root.appendingPathComponent("state.json")
        var other = fixture.snapshot
        other.progress[0].currentTime = 1
        let otherSource = LegacySource(kind: .inPlace, snapshot: other, filesRoot: fixture.documents, secrets: FixtureSecrets())

        try Data("{ not json".utf8).write(to: journal)
        XCTAssertThrowsError(try migrator.migrate(otherSource)) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .differentSourceAlreadyCommitted)
        }
        XCTAssertEqual(try Data(contentsOf: outcomeURL), committed)

        try? FileManager.default.removeItem(at: journal)
        XCTAssertThrowsError(try migrator.migrate(otherSource)) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .differentSourceAlreadyCommitted)
        }
        XCTAssertEqual(try Data(contentsOf: outcomeURL), committed)

        let sink = RecordingSecretSink()
        XCTAssertEqual(try migrator.migrate(fixture.inPlaceSource, secrets: sink), first)
        XCTAssertTrue(sink.adopted.isEmpty, "credentials recorded as adopted in the committed outcome must not be adopted again")
    }

    // MARK: 3. A committed migration is verified, and repaired from the untouched source

    func testDeletedOrReplacedAdoptedFilesAreDetectedAndRepairedFromTheUntouchedSource() throws {
        let before = try fixture.legacyTreeDigest()
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let track = try XCTUnwrap(try local(first, "local_li-audio").tracks.first?.file)
        let pdf = try XCTUnwrap(try local(first, "local_li-pdf").ebook?.file)
        try FileManager.default.removeItem(at: migrator.fileURL(for: track))
        try FileManager.default.removeItem(at: migrator.fileURL(for: pdf))
        try Data("%PDF-1.7 replaced!".utf8).write(to: migrator.fileURL(for: pdf))

        XCTAssertThrowsError(try migrator.committedOutcome()) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .committedMigrationDamaged)
        }
        let repaired = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertEqual(repaired, first)
        XCTAssertEqual(try contents(migrator, track), "audio-track-one")
        XCTAssertEqual(try contents(migrator, pdf), "%PDF-1.7 synthetic")
        XCTAssertEqual(try migrator.committedOutcome(), first)
        XCTAssertEqual(try fixture.legacyTreeDigest(), before)
    }

    func testAnAdoptedFileChangedInPlaceIsReportedInsteadOfBeingSilentlyReadopted() throws {
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let epub = try XCTUnwrap(try local(first, "local_li-epub").ebook?.file)
        let handle = try FileHandle(forWritingTo: migrator.fileURL(for: epub))
        handle.write(Data("XX".utf8))
        try handle.close()

        let repaired = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertFalse(try local(repaired, "local_li-epub").complete)
        XCTAssertNil(try local(repaired, "local_li-epub").ebook?.file)
        XCTAssertTrue(repaired.issues.contains { $0.code == .fileCorrupt && $0.legacyPath == "li-epub/book.epub" })
        XCTAssertTrue(try local(repaired, "local_li-pdf").complete)
    }

    func testAnOutcomeThatDisagreesWithItsJournalIsDamagedAndRepaired() throws {
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let outcomeURL = root.appendingPathComponent("outcome.json")
        let text = String(decoding: try Data(contentsOf: outcomeURL), as: UTF8.self)
        try Data(text.replacingOccurrences(of: first.sourceFingerprint, with: String(repeating: "0", count: 64)).utf8).write(to: outcomeURL)

        XCTAssertThrowsError(try migrator.committedOutcome()) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .committedMigrationDamaged)
        }
        XCTAssertEqual(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()), first)
        XCTAssertEqual(try migrator.committedOutcome(), first)
    }

    // MARK: 4. Recorded owners must corroborate the connection

    func testRowsWhoseRecordedOwnerConflictsWithTheirConnectionAreQuarantined() throws {
        // Saved on Bob's connection but recorded as Alice's download and progress.
        fixture.snapshot.localItems[1].serverUserId = "user-1"
        fixture.snapshot.progress[1].serverUserId = "user-1"
        // Saved on Alice's connection but recorded against another server.
        fixture.snapshot.localItems[2].serverAddress = "https://elsewhere.example.test"
        fixture.snapshot.progress[2].serverAddress = "https://elsewhere.example.test"
        fixture.snapshot.pendingDownloads = [
            LegacyPendingDownload(id: "dl-conflict", libraryItemId: "li-next", episodeId: nil, title: "Next", serverConnectionConfigId: "conn-a2",
                                  serverAddress: "https://books.example.test/abs", serverUserId: "user-1", completedParts: 0, totalParts: 1),
        ]
        let migrator = LegacyMigrator(root: fixture.migrationRoot())

        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let pdf = try local(outcome, "local_li-pdf")
        let epub = try local(outcome, "local_li-epub")
        XCTAssertNil(pdf.account)
        XCTAssertNil(epub.account)
        let bobDirectory = MigrationAccount(address: "https://books.example.test/abs", userID: "user-2")!
        XCTAssertNotEqual(pdf.ebook?.file?.path.split(separator: "/").first,
                          outcome.downloads.first { $0.account == bobDirectory }?.files.first?.file?.path.split(separator: "/").first)
        XCTAssertEqual(try contents(migrator, pdf.ebook?.file), "%PDF-1.7 synthetic", "quarantined data is kept, not dropped")
        XCTAssertNil(outcome.progress.first { $0.libraryItemID == "li-pdf" }?.account)
        XCTAssertNil(outcome.progress.first { $0.libraryItemID == "li-epub" }?.account)
        XCTAssertNil(outcome.issues.first { $0.code == .downloadInterrupted }?.account)
        let mismatched = Set(outcome.issues.filter { $0.code == .accountMismatch }.compactMap(\.libraryItemID))
        XCTAssertTrue(mismatched.isSuperset(of: ["li-pdf", "li-epub", "li-next"]), "\(mismatched)")
        XCTAssertFalse(outcome.accounts.contains { $0.account.server == "https://elsewhere.example.test" }, "a conflicting row must not create an account")
        XCTAssertEqual(try local(outcome, "local_li-audio").account, homeAlice)
    }

    // MARK: 5. Every legacy file of an item is enumerable from the outcome

    func testEveryLegacyFileOfAnItemIsListedWithItsAssociation() throws {
        let notes = try fixture.writeFile("li-audio/notes.pdf", "%PDF supplementary")
        fixture.snapshot.localItems[0].files.append(notes)
        let migrator = LegacyMigrator(root: fixture.migrationRoot())

        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let audio = try local(outcome, "local_li-audio")
        XCTAssertTrue(audio.complete)
        XCTAssertEqual(audio.legacyItem, fixture.snapshot.localItems[0])
        let byPath = Dictionary(uniqueKeysWithValues: audio.files.map { ($0.legacyPath, $0) })
        XCTAssertEqual(Set(byPath.keys), ["li-audio/01 Opening.mp3", "li-audio/02 Middle.mp3", "li-audio/cover.jpg", "li-audio/notes.pdf"])
        XCTAssertEqual(byPath["li-audio/01 Opening.mp3"]?.role, .track)
        XCTAssertEqual(byPath["li-audio/02 Middle.mp3"]?.trackIndex, 2)
        XCTAssertEqual(byPath["li-audio/cover.jpg"]?.role, .cover)
        let supplementary = try XCTUnwrap(byPath["li-audio/notes.pdf"])
        XCTAssertEqual(supplementary.role, .supplementary)
        XCTAssertEqual(supplementary.legacyFileID, notes.id)
        XCTAssertEqual(supplementary.mimeType, "application/pdf")
        XCTAssertEqual(try contents(migrator, supplementary.file), "%PDF supplementary")

        XCTAssertEqual(try local(outcome, "local_li-pdf").files.map(\.role), [.ebook])
        XCTAssertEqual(try local(outcome, "local_li-pod").files.first?.role, .episodeTrack)
        XCTAssertEqual(try local(outcome, "local_li-pod").files.first?.episodeID, "ep-1")
        let missing = try XCTUnwrap(try local(outcome, "local_li-missing").files.first)
        XCTAssertNil(missing.file)
        XCTAssertEqual(missing.legacyPath, "li-missing/gone.mp3")
    }

    // MARK: Audit: finished parts of an interrupted download

    func testFinishedPartsOfAnInterruptedDownloadAreAdoptedInsteadOfOrphaned() throws {
        try fixture.writeFile("li-next/01.mp3", "finished-part")
        fixture.snapshot.pendingDownloads = [
            LegacyPendingDownload(id: "dl-1", libraryItemId: "li-next", episodeId: nil, title: "Next Book", serverConnectionConfigId: "conn-a2",
                                  serverAddress: "https://books.example.test/abs", serverUserId: "user-2", completedParts: 1, totalParts: 2, mediaType: "book", parts: [
                                      LegacyDownloadPart(id: "part-1", filename: "01.mp3", path: "li-next/01.mp3", size: 13, completed: true, moved: true, role: .track, trackIndex: 1),
                                      LegacyDownloadPart(id: "part-2", filename: "02.mp3", path: "li-next/02.mp3", size: 99, completed: false, moved: false, role: .track, trackIndex: 2),
                                  ]),
        ]
        let migrator = LegacyMigrator(root: fixture.migrationRoot())

        let outcome = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        let interrupted = try XCTUnwrap(outcome.interruptedDownloads.first)
        XCTAssertEqual(interrupted.account, homeBob)
        XCTAssertEqual(interrupted.libraryItemID, "li-next")
        XCTAssertEqual(interrupted.parts.map(\.part.id), ["part-1", "part-2"])
        XCTAssertEqual(try contents(migrator, interrupted.parts[0].file), "finished-part")
        XCTAssertNil(interrupted.parts[1].file)
        XCTAssertTrue(outcome.issues.contains { $0.code == .downloadInterrupted && $0.libraryItemID == "li-next" })
        XCTAssertFalse(outcome.issues.contains { $0.legacyPath == "li-next/02.mp3" }, "an unfinished part is not a missing file")
    }
}
