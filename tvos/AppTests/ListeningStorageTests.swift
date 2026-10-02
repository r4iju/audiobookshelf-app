import XCTest
@testable import AudiobookshelfTV

/// An Apple TV gives apps no persistent files: only user defaults persist, and Application Support cannot be written on
/// a device ("You don't have permission to save the file NativeListening in the folder Application Support", #114). A
/// folder below a regular file refuses every write the same way in the simulator.
@MainActor final class ListeningStorageTests: XCTestCase {
    private struct NoCredentials: CredentialStore {
        func load() throws -> Credentials? { nil }
        func save(_ credentials: Credentials) throws {}
        func clear() throws {}
    }

    private var base: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("ListeningStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        suite = "ListeningStorageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    private func unwritableStorage() throws -> ListeningStorage {
        let blocker = base.appendingPathComponent("Application Support")
        try Data().write(to: blocker)
        return ListeningStorage(folder: blocker.appendingPathComponent("NativeListening", isDirectory: true), defaults: defaults)
    }

    private func sync(_ storage: ListeningStorage) -> ListeningSync { ListeningSync(api: APIClient(store: NoCredentials()), storage: storage) }

    private let account = try! AccountIdentity(server: "https://books.example.test/abs", userID: "user-1")

    private func write(_ position: Int, item: String = "book-0", padding: Int = 0) -> PublicationLedger.Write {
        PublicationLedger.Write(id: UUID(), account: account, itemID: item, episodeID: nil, method: "POST", path: "/abs/api/session/local-all",
                                body: Data("{\"currentTime\":\(position),\"note\":\"\(String(repeating: "x", count: padding))\"}".utf8),
                                issuedAt: Date().timeIntervalSince1970 * 1_000)
    }

    func testSentProgressAndResetsAreKeptAcrossRelaunchWhereFilesCannotBeWritten() throws {
        let storage = try unwritableStorage()
        let first = sync(storage)
        XCTAssertNoThrow(try first.publications.issue(write(10)), "Progress must be sendable on an Apple TV")
        let reset = ProgressResetIntent(account: account, itemID: "book-1", episodeID: nil, rowID: "row-1", requestedAt: 1_000)
        XCTAssertNoThrow(try first.beginReset(reset), "A confirmed reset must be saved on an Apple TV")

        let relaunched = sync(storage)
        XCTAssertTrue(relaunched.publications.unresolved(account: account, itemID: "book-0", episodeID: nil), "The unanswered write survives relaunch")
        XCTAssertEqual(try relaunched.pendingResets(), [reset], "The confirmed reset survives relaunch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.folder.path))
    }

    func testRecordsLeftInFilesByAnEarlierBuildAreReadAndKept() throws {
        let storage = ListeningStorage(folder: base.appendingPathComponent("NativeListening", isDirectory: true), defaults: defaults)
        let earlier = ListeningSync(api: APIClient(store: NoCredentials()), storage: ListeningStorage(folder: storage.folder, defaults: nil))
        try earlier.publications.issue(write(10))
        let reset = ProgressResetIntent(account: account, itemID: "book-1", episodeID: nil, rowID: nil, requestedAt: 1_000)
        try earlier.beginReset(reset)
        let files = try [storage.publicationsFile, storage.resetsFile].map { try Data(contentsOf: $0) }

        let current = sync(storage)
        XCTAssertTrue(current.publications.unresolved(account: account, itemID: "book-0", episodeID: nil), "The earlier unanswered write still holds")
        XCTAssertEqual(try current.pendingResets(), [reset])
        try current.publications.issue(write(20, item: "book-2"))
        try current.finishReset(reset)

        let relaunched = sync(storage)
        XCTAssertTrue(relaunched.publications.unresolved(account: account, itemID: "book-0", episodeID: nil))
        XCTAssertTrue(relaunched.publications.unresolved(account: account, itemID: "book-2", episodeID: nil))
        XCTAssertEqual(try relaunched.pendingResets(), [])
        XCTAssertEqual(try [storage.publicationsFile, storage.resetsFile].map { try Data(contentsOf: $0) }, files, "The earlier files are left as they were")
    }

    func testAWriteTheBoundedRecordCannotHoldIsNotSentAndKeepsTheEarlierRecord() throws {
        let storage = try unwritableStorage()
        let ledger = sync(storage).publications
        try ledger.issue(write(10))
        XCTAssertThrowsError(try ledger.issue(write(20, item: "book-1", padding: 200_000)), "A write that cannot be recorded must not be sent")
        let relaunched = sync(storage).publications
        XCTAssertTrue(relaunched.unresolved(account: account, itemID: "book-0", episodeID: nil))
        XCTAssertFalse(relaunched.unresolved(account: account, itemID: "book-1", episodeID: nil))
    }

    /// Space kept in defaults stays bounded however often the record becomes unreadable: one earlier copy is kept, and
    /// a second unreadable record is kept in place while nothing is sent.
    func testRepeatedlyUnreadableRecordsKeepOneBoundedCopyAndStopSending() throws {
        let storage = try unwritableStorage()
        let first = Data("{\"version\":1,\"writes\":[{".utf8), second = Data("{\"version\":1,\"writes\":[[".utf8)
        defaults.set(first, forKey: ListeningStorage.publicationsKey)
        _ = sync(storage)
        XCTAssertNotEqual(defaults.data(forKey: ListeningStorage.publicationsKey), first, "The first unreadable record is set aside and replaced")

        defaults.set(second, forKey: ListeningStorage.publicationsKey)
        let ledger = sync(storage).publications
        XCTAssertThrowsError(try ledger.issue(write(20))) { error in
            guard case PublicationLedger.Failure.unreadable = error else { return XCTFail("Expected the record to stay unreadable, got \(error)") }
        }
        let kept = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(ListeningStorage.publicationsKey) }
        XCTAssertEqual(kept.count, 2, "The record and one earlier copy: \(kept.keys.sorted())")
        XCTAssertEqual(kept[ListeningStorage.publicationsKey] as? Data, second, "The unreadable record stays in place")
        XCTAssertTrue(kept.values.contains { $0 as? Data == first }, "The earlier copy is kept")
    }
}
