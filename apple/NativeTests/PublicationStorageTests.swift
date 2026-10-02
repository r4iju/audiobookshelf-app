import XCTest

/// The record of sent progress on a volume that is full when an unreadable record is set aside. `ABS_FULL_VOLUME`
/// names a small, otherwise empty volume that `apple/scripts/verify-download-storage.sh` mounts.
@MainActor final class PublicationStorageTests: XCTestCase {
    private var volume: URL!
    private var filler: URL { volume.appendingPathComponent("filler") }
    private var folder: URL { volume.appendingPathComponent("listening") }
    private var file: URL { folder.appendingPathComponent("publications.json") }
    private let unreadable = Data("{\"version\":1,\"writes\":[{\"id\":".utf8)

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["ABS_FULL_VOLUME"] else {
            throw XCTSkip("Run through apple/scripts/verify-download-storage.sh, which mounts a small volume")
        }
        volume = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.removeItem(at: filler)
        try? FileManager.default.removeItem(at: folder)
    }

    override func tearDown() async throws {
        if let volume { try? FileManager.default.removeItem(at: filler); try? FileManager.default.removeItem(at: folder) }
    }

    /// Writes until the volume refuses another byte.
    private func fillVolume() throws {
        FileManager.default.createFile(atPath: filler.path, contents: nil)
        let handle = try FileHandle(forWritingTo: filler)
        defer { try? handle.close() }
        for size in [1 << 16, 4096, 512, 1] {
            let chunk = Data(repeating: 0, count: size)
            while (try? handle.write(contentsOf: chunk)) != nil {}
        }
        XCTAssertThrowsError(try Data([1]).write(to: volume.appendingPathComponent("probe")), "The volume must be full")
    }

    private func write(_ account: AccountIdentity, position: Int) -> PublicationLedger.Write {
        PublicationLedger.Write(id: UUID(), account: account, itemID: "book-0", episodeID: nil, method: "POST", path: "/abs/api/session/local-all",
                                body: Data("{\"currentTime\":\(position)}".utf8), issuedAt: Date().timeIntervalSince1970 * 1_000)
    }

    func testAnUnreadableRecordSetAsideOnAFullVolumeStillHoldsLaterWritesUntilARequestedRestart() throws {
        let account = try AccountIdentity(server: "https://books.example.test/abs", userID: "user-1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try unreadable.write(to: file)
        try fillVolume()

        let full = PublicationLedger(file: file)
        XCTAssertThrowsError(try full.issue(write(account, position: 10)), "Nothing is sent while the record cannot be replaced")

        try FileManager.default.removeItem(at: filler)
        let relaunched = PublicationLedger(file: file)
        XCTAssertThrowsError(try relaunched.issue(write(account, position: 20))) { error in
            guard case PublicationLedger.Failure.waiting = error else { return XCTFail("Expected the write to wait, got \(error)") }
        }
        let kept = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("publications-unreadable-") }
            .compactMap { try? Data(contentsOf: $0) }
        XCTAssertTrue(kept.contains(unreadable), "The unreadable record is kept")

        try relaunched.requestRestart(server: account.server)
        try relaunched.confirmRestart(server: account.server)
        XCTAssertNoThrow(try PublicationLedger(file: file).issue(write(account, position: 30)), "A confirmed restart asked for after it resolves the unknown writes")
    }
}
