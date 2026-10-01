import CryptoKit
import Foundation
import LegacyMigration
import XCTest

/// A committed migration only ever hands out regular files inside its own `Files` directory with
/// their committed content, whether checked at launch, on access or by a repair.
final class LegacyCommittedFileTests: XCTestCase {
    private var fixture: LegacyFixture!

    override func setUpWithError() throws {
        fixture = try LegacyFixture()
    }

    override func tearDown() {
        fixture.cleanUp()
    }

    private func local(_ outcome: MigrationOutcome, _ legacyLocalItemID: String) throws -> MigratedDownload {
        try XCTUnwrap(outcome.downloads.first { $0.legacyLocalItemID == legacyLocalItemID }, "missing download \(legacyLocalItemID)")
    }

    private func stored(_ migrator: LegacyMigrator, _ file: MigratedFile) -> URL {
        migrator.root.appendingPathComponent("Files").appendingPathComponent(file.path)
    }

    /// Inside the native container but outside the migration root, so the legacy tree digest
    /// still covers only legacy files.
    private var outsideMigration: URL { fixture.migrationRoot().deletingLastPathComponent() }

    private func type(at url: URL) throws -> FileAttributeType? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    }

    private func treeDigest(_ directory: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(path)
            guard try type(at: url) == .typeRegular else { continue }
            result[path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    private func assertDamaged(_ expression: @autoclosure () throws -> Any?, _ message: String, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), message, line: line) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .committedMigrationDamaged, message, line: line)
        }
    }

    func testTheLaunchCheckNeverReportsASameSizeChangeAsValid() throws {
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        XCTAssertEqual(try migrator.committedOutcome(), first)
        XCTAssertEqual(try migrator.committedOutcome(), first, "an unchanged migration stays valid across launches")
        let pdf = try XCTUnwrap(try local(first, "local_li-pdf").ebook?.file)
        let url = stored(migrator, pdf)
        let modified = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        let handle = try FileHandle(forWritingTo: url)
        handle.write(Data("%XXX".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)

        assertDamaged(try migrator.committedOutcome(), "same size and modification date, different bytes")
        assertDamaged(try migrator.fileURL(for: pdf), "a changed file must not be handed out")
        XCTAssertEqual(String(decoding: try Data(contentsOf: try migrator.fileURL(for: try XCTUnwrap(try local(first, "local_li-audio").tracks.first?.file))), as: UTF8.self),
                       "audio-track-one", "unchanged files stay usable")
    }

    func testAnAdoptedFileReplacedBySymlinkToMatchingBytesIsNotTrustedAndIsRepairedWithoutTouchingTheTarget() throws {
        let legacy = try fixture.legacyTreeDigest()
        let fileSystem = FaultInjectingFileSystem()
        let migrator = LegacyMigrator(root: fixture.migrationRoot(), fileSystem: fileSystem)
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let pdf = try XCTUnwrap(try local(first, "local_li-pdf").ebook?.file)
        let outside = outsideMigration.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = outside.appendingPathComponent("companion.pdf")
        try Data("%PDF-1.7 synthetic".utf8).write(to: target)
        try FileManager.default.removeItem(at: stored(migrator, pdf))
        try FileManager.default.createSymbolicLink(at: stored(migrator, pdf), withDestinationURL: target)

        assertDamaged(try migrator.committedOutcome(), "a symlink is not an adopted file, whatever it points at")
        assertDamaged(try migrator.fileURL(for: pdf), "a symlinked file must not be handed out")

        fileSystem.failAfterTransfers = fileSystem.transfers.count
        XCTAssertThrowsError(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()))
        fileSystem.failAfterTransfers = nil
        assertDamaged(try migrator.committedOutcome(), "a failed repair stays damaged")
        var other = fixture.snapshot
        other.progress[0].currentTime = 1
        XCTAssertThrowsError(try migrator.migrate(LegacySource(kind: .inPlace, snapshot: other, filesRoot: fixture.documents))) { error in
            XCTAssertEqual(error as? LegacyMigrationError, .differentSourceAlreadyCommitted, "a failed repair keeps the original fingerprint")
        }
        XCTAssertEqual(try fixture.legacyTreeDigest(), legacy)

        let repaired = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertEqual(repaired, first)
        XCTAssertEqual(try type(at: stored(migrator, pdf)), .typeRegular)
        XCTAssertEqual(try migrator.committedOutcome(), first)
        XCTAssertEqual(try Data(contentsOf: target), Data("%PDF-1.7 synthetic".utf8), "the symlink target is not the migration's to change")
        XCTAssertEqual(try fixture.legacyTreeDigest(), legacy)
    }

    func testAParentDirectoryReplacedBySymlinkIsNeitherTrustedNorWrittenThrough() throws {
        let legacy = try fixture.legacyTreeDigest()
        let migrator = LegacyMigrator(root: fixture.migrationRoot())
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let track = try XCTUnwrap(try local(first, "local_li-audio").tracks.first?.file)
        let itemDirectory = stored(migrator, track).deletingLastPathComponent().deletingLastPathComponent()
        let outside = outsideMigration.appendingPathComponent("OutsideItem")
        try FileManager.default.moveItem(at: itemDirectory, to: outside)
        try FileManager.default.createSymbolicLink(at: itemDirectory, withDestinationURL: outside)
        let outsideBefore = try treeDigest(outside)
        XCTAssertFalse(outsideBefore.isEmpty)

        assertDamaged(try migrator.committedOutcome(), "a file reached through a symlinked directory is outside the migration")
        assertDamaged(try migrator.fileURL(for: track), "a file under a symlinked directory must not be handed out")

        let repaired = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())

        XCTAssertEqual(repaired, first)
        XCTAssertEqual(try type(at: itemDirectory), .typeDirectory)
        XCTAssertEqual(try type(at: stored(migrator, track)), .typeRegular)
        XCTAssertEqual(try migrator.committedOutcome(), first)
        XCTAssertEqual(try treeDigest(outside), outsideBefore, "nothing is written or removed through the symlink")
        XCTAssertEqual(try fixture.legacyTreeDigest(), legacy)
    }

    func testCommittedDescriptorsThatLeaveTheFilesDirectoryAreRejected() throws {
        let root = fixture.migrationRoot()
        let migrator = LegacyMigrator(root: root)
        let first = try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink())
        let pdf = try XCTUnwrap(try local(first, "local_li-pdf").ebook?.file)
        let decoy = outsideMigration.appendingPathComponent("decoy.pdf")
        try Data("%PDF-1.7 synthetic".utf8).write(to: decoy)
        let escaping = "../../decoy.pdf"
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Files").appendingPathComponent(escaping)), Data("%PDF-1.7 synthetic".utf8))
        let outcomeURL = root.appendingPathComponent("outcome.json")
        var text = String(decoding: try Data(contentsOf: outcomeURL), as: UTF8.self)
        let encoded = { (path: String) in "\"path\":\"\(path.replacingOccurrences(of: "/", with: "\\/"))\"" }
        XCTAssertTrue(text.contains(encoded(pdf.path)))
        text = text.replacingOccurrences(of: encoded(pdf.path), with: encoded(escaping))
        try Data(text.utf8).write(to: outcomeURL)
        var escapingFile = pdf
        escapingFile.path = escaping

        assertDamaged(try migrator.committedOutcome(), "a committed path leaving Files is damage, even with matching bytes")
        assertDamaged(try migrator.fileURL(for: escapingFile), "a descriptor leaving Files must not resolve")

        XCTAssertEqual(try migrator.migrate(fixture.inPlaceSource, secrets: RecordingSecretSink()), first)
        XCTAssertEqual(try migrator.committedOutcome(), first)
        XCTAssertEqual(try Data(contentsOf: decoy), Data("%PDF-1.7 synthetic".utf8))
    }
}
