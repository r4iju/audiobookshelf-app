import XCTest

/// Recovery of finished downloads when a later part of the same entry fails.
@MainActor final class DownloadRecoveryTests: XCTestCase {
    private let stub = StubServer()
    private let credentials = MemoryCredentials()
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("download-recovery-\(UUID().uuidString)", isDirectory: true)
        credentials.value = Credentials(server: "https://books.example.test/abs", accessToken: "SYNTHETIC", refreshToken: nil, userID: "user-1", username: "user-1")
        stub.route("GET", "/abs/api/me") { _ in .json(200, StubUser.json(id: "user-1")) }
    }

    override func tearDown() async throws {
        StubProtocol.server = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func store(_ api: APIClient) -> NativeDownloads {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return NativeDownloads(api: api, directory: root, configuration: configuration)
    }

    private func serveItem(ebook: Bool) {
        stub.route("GET", "/abs/api/items/book-1") { _ in
            var media: [String: Any] = ["metadata": ["title": "Synthetic book"], "duration": 1,
                                        "tracks": [["contentUrl": "/api/items/book-1/file/ino-1", "mimeType": "audio/wav", "metadata": ["filename": "01.wav", "ext": ".wav"], "startOffset": 0, "duration": 1]]]
            if ebook { media["ebookFile"] = ["ino": "ino-pdf", "ebookFormat": "pdf", "metadata": ["filename": "book.pdf", "ext": ".pdf"]] }
            return .json(200, ["id": "book-1", "mediaType": "book", "media": media])
        }
    }

    private func wait(_ downloads: NativeDownloads, until condition: (NativeDownloads.Entry?) -> Bool) async throws {
        for _ in 0..<50 where !condition(downloads.visible.first) { try await Task.sleep(nanoseconds: 100_000_000) }
    }

    /// The server item gains a PDF after its audio was downloaded, and fetching the PDF fails. The finished audio must
    /// stay playable offline, now and after a relaunch, while the entry offers a retry for the PDF.
    func testAudioStaysPlayableOfflineWhenAPDFAddedLaterFailsToDownload() async throws {
        let audio = AdoptionHarness.wav(seconds: 1, tone: 220)
        stub.route("GET", "/abs/api/items/book-1/file/ino-1/download") { _ in .file(200, "audio/wav", audio) }
        stub.route("GET", "/abs/api/items/book-1/file/ino-pdf/download") { _ in .status(503) }
        let api = APIClient(store: credentials, session: stub.session())
        try api.restoreSavedCredentials()
        var downloads = store(api)
        let item = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: ["id": "book-1", "mediaType": "book", "media": ["metadata": ["title": "Synthetic book"]]]))

        serveItem(ebook: false)
        await downloads.enqueue(item: item, episode: nil)
        try await wait(downloads) { $0?.state == .ready }
        XCTAssertEqual(downloads.visible.first?.state, .ready)

        serveItem(ebook: true)
        await downloads.enqueue(item: item, episode: nil)
        try await wait(downloads) { $0?.state == .failed }
        let failed = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(failed.state, .failed, "The PDF failure is reported on the entry, with a retry")
        XCTAssertEqual(try downloads.audio(failed).files.map { try Data(contentsOf: $0) }, [audio])

        downloads = store(api)
        try await wait(downloads) { $0 != nil }
        let relaunched = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(try downloads.audio(relaunched).files.map { try Data(contentsOf: $0) }, [audio])
    }

    /// A transfer the system could not write for a reason other than space, here a permission failure, must not be
    /// reported as a full device.
    func testFileWriteFailureWithoutAStorageCauseIsNotReportedAsInsufficientStorage() async throws {
        let permission = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        stub.route("GET", "/abs/api/items/book-1/file/ino-1/download") { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile, userInfo: [NSUnderlyingErrorKey: permission]))
        }
        let api = APIClient(store: credentials, session: stub.session())
        try api.restoreSavedCredentials()
        let downloads = store(api)
        serveItem(ebook: false)
        let item = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: ["id": "book-1", "mediaType": "book", "media": ["metadata": ["title": "Synthetic book"]]]))
        await downloads.enqueue(item: item, episode: nil)
        try await wait(downloads) { $0?.state == .failed }
        let failed = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNotNil(failed.error)
        XCTAssertNotEqual(failed.error, "There is not enough storage on this device for this download. Free up space, then retry.")
        XCTAssertEqual(stub.requests("GET", "/abs/api/items/book-1/file/ino-1/download").count, 1)
    }
}
