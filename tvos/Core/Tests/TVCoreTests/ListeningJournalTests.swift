import XCTest
@testable import TVCore

final class ListeningJournalTests: XCTestCase {
    @MainActor
    func testRecoveredSessionsKeepUnsentListeningAndRemoveAcknowledgedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file)
        let unsent = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        try journal.record(id: unsent, position: 14, listened: 8)
        let acknowledged = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        let sent = try XCTUnwrap(journal.pending(account: account).first { $0.id == acknowledged })
        try journal.acknowledge(sent)
        let reopened = try ListeningJournal(file: file)
        try reopened.finishRecoveredSessions()
        let pending = reopened.pending(account: account)
        XCTAssertEqual(pending.map(\.id), [unsent])
        XCTAssertEqual(pending.first?.currentTime, 14)
        XCTAssertEqual(pending.first?.timeListening, 8)
        try reopened.acknowledge(XCTUnwrap(pending.first))
        XCTAssertTrue(try ListeningJournal(file: file).pending(account: account).isEmpty)
    }

    @MainActor
    func testUnreadableJournalIsPreservedForRecovery() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let saved = Data("unreadable journal".utf8)
        try saved.write(to: file)
        XCTAssertThrowsError(try ListeningJournal(file: file))
        XCTAssertEqual(try Data(contentsOf: file), saved)
    }

    @MainActor
    func testFailedDiskWriteKeepsPreviouslySavedListening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        try journal.record(id: id, position: 9, listened: 3)
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try journal.record(id: id, position: 14, listened: 5))
        XCTAssertEqual(journal.pending(account: account).first?.currentTime, 9)
        XCTAssertEqual(journal.pending(account: account).first?.timeListening, 3)
        try FileManager.default.removeItem(at: file)
        try saved.write(to: file)
        XCTAssertEqual(try ListeningJournal(file: file).pending(account: account).first?.currentTime, 9)
    }

    @MainActor
    func testPersistedListeningReopensWithCumulativeTotalsAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://Books.Example:443/abs/", userID: "reader")
        let other = try AccountIdentity(server: "https://books.example/abs", userID: "another-reader")
        let journal = try ListeningJournal(file: file)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device", at: Date(timeIntervalSince1970: 1000))
        try journal.record(id: id, position: 12, listened: 6, at: Date(timeIntervalSince1970: 1006))
        let reopened = try ListeningJournal(file: file)
        let equivalent = try AccountIdentity(server: "https://books.example/abs", userID: "reader")
        let record = try XCTUnwrap(reopened.pending(account: equivalent).first)
        XCTAssertEqual(record.currentTime, 12)
        XCTAssertEqual(record.timeListening, 6)
        XCTAssertEqual(record.updatedAt, 1_006_000)
        XCTAssertTrue(reopened.pending(account: other).isEmpty)
        try reopened.record(id: id, position: 14, listened: 2, at: Date(timeIntervalSince1970: 1008))
        XCTAssertEqual(try ListeningJournal(file: file).pending(account: equivalent).first?.timeListening, 8)
    }

    @MainActor
    func testAcknowledgingAnOlderSnapshotDoesNotRetireNewerListening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device", at: Date(timeIntervalSince1970: 1000))
        try journal.record(id: id, position: 9, listened: 3, at: Date(timeIntervalSince1970: 1003))
        let sent = try XCTUnwrap(journal.pending(account: account).first)
        try journal.record(id: id, position: 10, listened: 1, at: Date(timeIntervalSince1970: 1004))
        try journal.acknowledge(sent)
        let reopened = try ListeningJournal(file: file)
        XCTAssertEqual(reopened.pending(account: account).first?.currentTime, 10)
        try reopened.finish(id: id)
        let latest = try XCTUnwrap(reopened.pending(account: account).first)
        try reopened.acknowledge(latest)
        XCTAssertTrue(try ListeningJournal(file: file).pending(account: account).isEmpty)
    }

    private static func media() throws -> ListeningMedia {
        let item = try JSONDecoder().decode(LibraryItem.self, from: Data(#"{"id":"book","mediaType":"book","media":{"metadata":{"title":"A Story","authorName":"Writer"},"duration":20}}"#.utf8))
        let session = try JSONDecoder().decode(PlaybackSession.self, from: Data(#"{"id":"stream","currentTime":6,"duration":20,"audioTracks":[{"contentUrl":"/audio/0","startOffset":0,"duration":20}]}"#.utf8))
        return ListeningMedia(item: item, session: session)
    }
}
