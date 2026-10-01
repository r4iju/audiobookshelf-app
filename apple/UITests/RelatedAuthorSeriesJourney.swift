import XCTest

/// Story #21 on iPhone: an author or series opens with its metadata and server order and leads to the intended book.
/// Needs the related fixture on 27765, which apple/scripts/verify-related.sh starts.
@MainActor final class RelatedAuthorSeriesJourney: NativeJourney {
    static let fixture = "http://127.0.0.1:27765/abs"

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ABS_RELATED_QA"] == "1", "Run apple/scripts/verify-related.sh, which starts the related fixture on 27765.")
        try await RelatedFixture.configure(fail: nil)
    }

    private func searchAndOpen(_ text: String, result identifier: String) -> XCUIApplication {
        connectSelectAndRestore(serverURL: Self.fixture, verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["Search library"].waitForExistence(timeout: 10))
        app.buttons["Search library"].tap()
        app.textFields["library-search"].tap()
        app.textFields["library-search"].typeText(text + "\n")
        let result = app.buttons[identifier]
        for _ in 0..<6 where !result.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(result.exists, app.debugDescription)
        result.tap()
        return app
    }

    func testSearchOpensAuthorWithBioSeriesAndEveryBook() async throws {
        let app = searchAndOpen("qa", result: "search-author-author")
        XCTAssertTrue(app.staticTexts["author-name"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["author-name"].label, "Audiobookshelf QA")
        XCTAssertTrue(app.staticTexts["author-bio"].label.hasPrefix("Audiobookshelf QA writes synthetic stories"))
        XCTAssertEqual(app.staticTexts["author-count"].label, "61 titles")
        XCTAssertTrue(app.images["author-image"].waitForExistence(timeout: 10), "The server's author image is shown")
        XCTAssertTrue(app.buttons["author-series.series-saga"].exists)
        XCTAssertTrue(app.buttons["author-series.series-evening"].exists)
        capture("mobile-author")
        let last = app.buttons["author-book.book-60"]
        for _ in 0..<40 where !last.exists { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 10), "Scrolling loads the author's second page")
        let observed = try await RelatedFixture.requests()
        let filter = "authors." + Data("author".utf8).base64EncodedString()
        XCTAssertTrue(observed.contains { $0.path == "/api/authors/author" })
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/items" && $0.query["filter"] == filter && $0.query["page"] == "1" })
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/series" && $0.query["filter"] == filter })
    }

    func testSeriesFollowsServerSequenceAndOpensTheIntendedBook() async throws {
        let app = searchAndOpen("saga", result: "search-series-series-saga")
        XCTAssertTrue(app.staticTexts["series-name"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["series-name"].label, "The Tomorrow Saga")
        XCTAssertEqual(app.staticTexts["series-description"].label, "Read in order: each story picks up where the last one ends.")
        let finished = try await RelatedFixture.finished("series-saga")
        XCTAssertEqual(app.staticTexts["series-progress"].label, "4 books · \(finished) finished")
        let ids = ["book-5", "book-2", "book-9", "book-1"]
        XCTAssertTrue(app.buttons["series-book.book-1"].waitForExistence(timeout: 10))
        let positions = ids.map { app.buttons["series-book.\($0)"].frame.minY }
        XCTAssertEqual(positions, positions.sorted(), "Books follow the server's sequence order")
        XCTAssertEqual(ids.map { app.staticTexts["series-sequence.\($0)"].label }, ["Book 1", "Book 2", "Book 2.5", "Book 10"])
        capture("mobile-series")
        app.buttons["series-book.book-9"].tap()
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 10"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["play-book"].exists)
        let observed = try await RelatedFixture.requests()
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/series/series-saga" && $0.query["include"] == "progress" })
        XCTAssertFalse(observed.contains { $0.path.hasPrefix("/api/series/") }, "Series details come from the library the books are listed from")
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/items" && $0.query["filter"] == "series." + Data("series-saga".utf8).base64EncodedString() && $0.query["sort"] == "sequence" })
    }

    func testBookDetailsLeadToItsSeriesAndAuthor() {
        connectSelectAndRestore(serverURL: Self.fixture, verifyRestoration: false)
        let app = XCUIApplication()
        let book = app.buttons["book-book-2"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        let series = app.buttons["detail-series.series-saga"]
        XCTAssertTrue(series.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(series.label, "The Tomorrow Saga, book 2")
        series.tap()
        XCTAssertTrue(app.buttons["series-book.book-2"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let author = app.buttons["detail-author.author"]
        XCTAssertTrue(author.waitForExistence(timeout: 10))
        author.tap()
        XCTAssertTrue(app.staticTexts["author-name"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["detail-series.series-saga"].waitForExistence(timeout: 10), "Back returns to the details that opened the author")
    }

    func testSeriesFailureRecoversWithRetry() async throws {
        try await RelatedFixture.configure(fail: "series")
        let app = searchAndOpen("saga", result: "search-series-series-saga")
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15), app.debugDescription)
        retry.tap()
        XCTAssertTrue(app.buttons["series-book.book-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["series-name"].label, "The Tomorrow Saga")
    }
}

enum RelatedFixture {
    struct Request: Decodable { let path: String; let query: [String: String] }
    private struct Observed: Decodable { let requests: [Request]; let finished: [String: Int] }

    static func configure(fail: String?) async throws {
        var request = URLRequest(url: URL(string: RelatedAuthorSeriesJourney.fixture + "/__related__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fail": fail.map { $0 as Any } ?? NSNull()])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    static func requests() async throws -> [Request] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: RelatedAuthorSeriesJourney.fixture + "/__related__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data).requests
    }

    /// How many books of the series the server now counts as finished.
    static func finished(_ series: String) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: RelatedAuthorSeriesJourney.fixture + "/__related__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data).finished[series] ?? -1
    }
}
