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

    func testSavingFailedDownloadAgainRestoresPDFWithoutDownloadingFinishedAudio() async throws {
        let audio = AdoptionHarness.wav(seconds: 1, tone: 220)
        let pdf = Data("%PDF-1.4 recovered companion".utf8)
        let audioPath = "/abs/api/items/book-1/file/ino-1/download"
        let pdfPath = "/abs/api/items/book-1/file/ino-pdf/download"
        stub.route("GET", audioPath) { _ in .file(200, "audio/wav", audio) }
        stub.route("GET", pdfPath) { _ in .status(503) }
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
        XCTAssertEqual(downloads.visible.first?.state, .failed)

        stub.route("GET", pdfPath) { _ in .file(200, "application/pdf", pdf) }
        await downloads.enqueue(item: item, episode: nil)
        try await wait(downloads) { $0?.state == .ready }
        let restored = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(restored.state, .ready, "Saving an existing failed download retries its unfinished parts")
        XCTAssertNil(restored.error)
        XCTAssertEqual(try downloads.audio(restored).files.map { try Data(contentsOf: $0) }, [audio])
        XCTAssertEqual(try Data(contentsOf: downloads.ebookURL(restored)), pdf)
        XCTAssertEqual(stub.requests("GET", audioPath).count, 1, "Completed audio is retained")
        XCTAssertEqual(stub.requests("GET", pdfPath).count, 2)

        downloads = store(api)
        try await wait(downloads) { $0 != nil }
        let relaunched = try XCTUnwrap(downloads.visible.first)
        XCTAssertEqual(relaunched.state, .ready)
        XCTAssertEqual(try downloads.audio(relaunched).files.map { try Data(contentsOf: $0) }, [audio])
        XCTAssertEqual(try Data(contentsOf: downloads.ebookURL(relaunched)), pdf)
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

    /// Server 2.30 lists each audio and ebook file's size in its `metadata`. A body that ends early without a
    /// Content-Length must not be saved as the finished file when the server said how large it is, while a transfer
    /// with neither a Content-Length nor a listed size stays acceptable.
    func testUnsizedTransferShorterThanTheListedFileSizeIsNotSavedAsFinished() async throws {
        let audio = AdoptionHarness.wav(seconds: 1, tone: 220)
        let pdf = Data("%PDF-1.4 synthetic".utf8) + Data(repeating: 32, count: 2048)
        stub.route("GET", "/abs/api/items/book-1/file/ino-1/download") { _ in .unsizedFile(200, "audio/wav", audio.prefix(audio.count / 2)) }
        stub.route("GET", "/abs/api/items/book-1/file/ino-pdf/download") { _ in .unsizedFile(200, "application/pdf", pdf.prefix(100)) }
        stub.route("GET", "/abs/api/items/book-1") { _ in
            .json(200, ["id": "book-1", "mediaType": "book",
                        "media": ["metadata": ["title": "Synthetic book"], "duration": 1,
                                  "tracks": [["contentUrl": "/api/items/book-1/file/ino-1", "mimeType": "audio/wav", "metadata": ["filename": "01.wav", "ext": ".wav", "size": audio.count], "startOffset": 0, "duration": 1]],
                                  "ebookFile": ["ino": "ino-pdf", "ebookFormat": "pdf", "metadata": ["filename": "book.pdf", "ext": ".pdf", "size": pdf.count]]]])
        }
        stub.route("GET", "/abs/api/items/book-2") { _ in
            .json(200, ["id": "book-2", "mediaType": "book",
                        "media": ["metadata": ["title": "Unsized book"], "duration": 1,
                                  "tracks": [["contentUrl": "/api/items/book-2/file/ino-2", "mimeType": "audio/wav", "metadata": ["filename": "02.wav", "ext": ".wav"], "startOffset": 0, "duration": 1]]]])
        }
        stub.route("GET", "/abs/api/items/book-2/file/ino-2/download") { _ in .unsizedFile(200, "audio/wav", audio) }
        let api = APIClient(store: credentials, session: stub.session())
        try api.restoreSavedCredentials()
        let downloads = store(api)
        for id in ["book-1", "book-2"] {
            let item = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: ["id": id, "mediaType": "book", "media": ["metadata": ["title": id]]]))
            await downloads.enqueue(item: item, episode: nil)
        }
        for _ in 0..<50 where downloads.visible.contains(where: { $0.state == .queued }) { try await Task.sleep(nanoseconds: 100_000_000) }
        let truncated = try XCTUnwrap(downloads.visible.first { $0.media.libraryItemID == "book-1" })
        XCTAssertEqual(truncated.state, .failed)
        XCTAssertFalse(truncated.audioAvailable, "Half of the audio file must not count as downloaded")
        XCTAssertFalse(truncated.ebookAvailable, "Part of the PDF must not count as downloaded")
        let unsized = try XCTUnwrap(downloads.visible.first { $0.media.libraryItemID == "book-2" })
        XCTAssertEqual(unsized.state, .ready, "Without a Content-Length or a listed size the transfer is accepted")
        XCTAssertEqual(try downloads.audio(unsized).files.map { try Data(contentsOf: $0) }, [audio])
    }
}
