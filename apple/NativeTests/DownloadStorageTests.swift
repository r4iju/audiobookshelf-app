import XCTest

/// Downloads on a volume that fills up while a transfer is running. `ABS_FULL_VOLUME` names a small, otherwise empty
/// volume that `apple/scripts/verify-download-storage.sh` mounts for this test; the store keeps its files there.
@MainActor final class DownloadStorageTests: XCTestCase {
    private let stub = StubServer()
    private let credentials = MemoryCredentials()
    private var volume: URL!
    private var filler: URL { volume.appendingPathComponent("filler") }
    private let download = "/abs/api/items/book-1/file/ino-1/download"

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["ABS_FULL_VOLUME"] else {
            throw XCTSkip("Run through apple/scripts/verify-download-storage.sh, which mounts a small volume")
        }
        volume = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.removeItem(at: filler)
        credentials.value = Credentials(server: "https://books.example.test/abs", accessToken: "SYNTHETIC", refreshToken: nil, userID: "user-1", username: "user-1")
        stub.route("GET", "/abs/api/me") { _ in .json(200, StubUser.json(id: "user-1")) }
        stub.route("GET", "/abs/api/items/book-1") { _ in
            .json(200, ["id": "book-1", "mediaType": "book",
                        "media": ["metadata": ["title": "Synthetic book"], "duration": 1,
                                  "tracks": [["contentUrl": "/api/items/book-1/file/ino-1", "mimeType": "audio/wav", "metadata": ["filename": "01.wav", "ext": ".wav"], "startOffset": 0, "duration": 1]]]])
        }
    }

    override func tearDown() async throws {
        StubProtocol.server = nil
        if let volume { try? FileManager.default.removeItem(at: filler); try? FileManager.default.removeItem(at: volume.appendingPathComponent("downloads")) }
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

    func testFullStorageFailsTheDownloadOnceWithAStorageMessageAndRetryCompletesAfterSpaceIsFreed() async throws {
        let audio = AdoptionHarness.wav(seconds: 1, tone: 220)
        let released = NSCondition()
        var open = false
        stub.route("GET", download) { _ in
            released.lock(); while !open { released.wait() }; released.unlock()
            return .file(200, "audio/wav", audio)
        }
        StubProtocol.server = stub
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(store: credentials, session: stub.session())
        try api.restoreSavedCredentials()
        let downloads = NativeDownloads(api: api, directory: volume.appendingPathComponent("downloads", isDirectory: true), configuration: configuration)
        XCTAssertNil(downloads.error)
        let item = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: ["id": "book-1", "mediaType": "book", "media": ["metadata": ["title": "Synthetic book"]]]))
        await downloads.enqueue(item: item, episode: nil)
        XCTAssertNil(downloads.error)
        for _ in 0..<50 where stub.requests("GET", download).isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(stub.requests("GET", download).count, 1)

        try fillVolume()
        released.lock(); open = true; released.broadcast(); released.unlock()
        for _ in 0..<30 where downloads.visible.first?.state == .queued { try await Task.sleep(nanoseconds: 100_000_000) }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(stub.requests("GET", download).count, 1, "A full device must not restart the transfer again and again")
        let failed = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.error, "There is not enough storage on this device for this download. Free up space, then retry.")

        try FileManager.default.removeItem(at: filler)
        await downloads.retry(failed)
        for _ in 0..<50 where downloads.visible.first?.state != .ready { try await Task.sleep(nanoseconds: 100_000_000) }
        let ready = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(try downloads.audio(ready).files.map { try Data(contentsOf: $0) }, [audio])
    }
}
