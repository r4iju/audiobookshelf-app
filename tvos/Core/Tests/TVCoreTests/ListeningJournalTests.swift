import XCTest
@testable import TVCore

final class ListeningJournalTests: XCTestCase {
    @MainActor
    func testDuplicateRecordIDsAreRejectedWithoutChangingSource() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file)
        _ = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let records = try XCTUnwrap(document["records"] as? [[String: Any]])
        document["records"] = records + records
        let corrupt = try JSONSerialization.data(withJSONObject: document)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try ListeningJournal(file: file))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    @MainActor
    func testBoundedJournalEvictsOldRemoteCacheButKeepsPendingListening() throws {
        let suite = "ListeningJournalQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        try journal.record(id: id, position: 14, listened: 8)
        for index in 0..<100 { try journal.rememberRemotePosition(account: account, itemID: "remote-\(index)", episodeID: nil, time: 2, updatedAt: Double(index)) }
        let reopened = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        XCTAssertEqual(reopened.pending(account: account).map(\.id), [id])
        XCTAssertEqual(reopened.pending(account: account).first?.timeListening, 8)
        XCTAssertEqual(reopened.cachedPosition(account: account, itemID: "remote-99", episodeID: nil, newerThan: 0), 2)
    }

    @MainActor
    func testOversizedFileJournalCanDrainBeforeSwitchingToPersistentStorage() throws {
        let suite = "ListeningJournalQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let old = try ListeningJournal(file: file)
        for _ in 0..<6 { _ = try old.begin(account: account, media: Self.media(), deviceID: "device") }
        let migrated = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        try migrated.finishRecoveredSessions()
        XCTAssertEqual(migrated.pending(account: account).count, 6)
        XCTAssertThrowsError(try migrated.begin(account: account, media: Self.media(), deviceID: "device"))
        for record in migrated.pending(account: account) { try migrated.acknowledge(record) }
        XCTAssertNotNil(defaults.data(forKey: "NativeListeningJournal"))
        try FileManager.default.removeItem(at: file)
        let reopened = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        XCTAssertTrue(reopened.pending(account: account).isEmpty)
        XCTAssertNoThrow(try reopened.begin(account: account, media: Self.media(), deviceID: "device"))
    }

    @MainActor
    func testPersistentJournalSurvivesFilePurgeWithoutCrossAccountReplay() throws {
        let suite = "ListeningJournalQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let other = try AccountIdentity(server: "https://books.example", userID: "another")
        let journal = try ListeningJournal(file: file, persistentDefaults: defaults)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        try journal.record(id: id, position: 14, listened: 8)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        let reopened = try ListeningJournal(file: file, persistentDefaults: defaults)
        try reopened.finishRecoveredSessions()
        let pending = reopened.pending(account: account)
        XCTAssertEqual(pending.map(\.id), [id])
        XCTAssertEqual(pending.first?.timeListening, 8)
        XCTAssertTrue(reopened.pending(account: other).isEmpty)
        try reopened.acknowledge(XCTUnwrap(pending.first))
        XCTAssertTrue(try ListeningJournal(file: file, persistentDefaults: defaults).pending(account: account).isEmpty)
    }

    @MainActor
    func testPersistentCapacityFailureRetainsUnacknowledgedListening() throws {
        let suite = "ListeningJournalQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let journal = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device")
        try journal.record(id: id, position: 14, listened: 8)
        let huge = ListeningMedia(itemID: "huge", episodeID: nil, title: String(repeating: "Long title ", count: 1000), author: "Writer", mediaType: "book", duration: 100, startTime: 0)
        XCTAssertThrowsError(try journal.begin(account: account, media: huge, deviceID: "device"))
        let reopened = try ListeningJournal(file: file, persistentDefaults: defaults, maximumPersistentBytes: 1500)
        XCTAssertEqual(reopened.pending(account: account).map(\.id), [id])
        XCTAssertEqual(reopened.pending(account: account).first?.timeListening, 8)
    }

    @MainActor
    func testCorruptPersistentJournalDoesNotReplayStaleFile() throws {
        let suite = "ListeningJournalQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let account = try AccountIdentity(server: "https://books.example", userID: "reader")
        let old = try ListeningJournal(file: file)
        _ = try old.begin(account: account, media: Self.media(), deviceID: "device")
        defaults.set(Data("damaged".utf8), forKey: "NativeListeningJournal")
        XCTAssertThrowsError(try ListeningJournal(file: file, persistentDefaults: defaults))
        XCTAssertEqual(defaults.data(forKey: "NativeListeningJournal"), Data("damaged".utf8))
    }

    @MainActor
    func testOfflineResumeRetainsAcknowledgedPositionButRespectsANewerRemoteSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("listening.json")
        let account = try AccountIdentity(server: "https://Books.Example:443/abs/", userID: "reader")
        let equivalent = try AccountIdentity(server: "https://books.example/abs", userID: "reader")
        let other = try AccountIdentity(server: "https://books.example/abs", userID: "another-reader")
        let journal = try ListeningJournal(file: file)
        let id = try journal.begin(account: account, media: Self.media(), deviceID: "device", at: Date(timeIntervalSince1970: 1000))
        try journal.record(id: id, position: 12, listened: 6, at: Date(timeIntervalSince1970: 1006))
        try journal.finish(id: id)
        try journal.acknowledge(XCTUnwrap(journal.pending(account: account).first))
        let reopened = try ListeningJournal(file: file)
        XCTAssertTrue(reopened.pending(account: equivalent).isEmpty)
        XCTAssertEqual(reopened.cachedPosition(account: equivalent, itemID: "book", episodeID: nil, newerThan: 1_005_000), 12)
        XCTAssertNil(reopened.cachedPosition(account: equivalent, itemID: "book", episodeID: nil, newerThan: 1_007_000))
        XCTAssertNil(reopened.cachedPosition(account: other, itemID: "book", episodeID: nil, newerThan: 0))
        XCTAssertNil(reopened.cachedPosition(account: equivalent, itemID: "book", episodeID: "episode", newerThan: 0))
    }

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
