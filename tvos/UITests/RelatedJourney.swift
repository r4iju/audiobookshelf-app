import XCTest

/// Story #21: an author or series leads, with its metadata and server order, to the intended book.
final class RelatedJourney: TVJourney {
    override func setUp() async throws {
        try await super.setUp()
        try await RelatedFixture.configure(fail: nil)
    }

    func searchAndOpen(_ text: String, result identifier: String) {
        signIn()
        waitForHome()
        tab("Search")
        search(text)
        let result = app.buttons[identifier]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        select(result)
    }

    func testSearchOpensAuthorWithBioSeriesAndEveryBook() async throws {
        searchAndOpen("qa", result: "search.author.author")
        XCTAssertTrue(app.staticTexts["author-name"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(label("author-name"), "Audiobookshelf QA")
        XCTAssertTrue(label("author-bio").hasPrefix("Audiobookshelf QA writes synthetic stories"))
        XCTAssertEqual(label("author-count"), "61 titles")
        XCTAssertTrue(app.images["author-image"].waitForExistence(timeout: 10), "The server's author image is shown")
        XCTAssertTrue(app.buttons["author-series.series-saga"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["author-series.series-evening"].exists)
        capture("author")
        let last = app.buttons["author-book.book-60"]
        for _ in 0..<30 where !last.exists { remote.press(.down) }
        XCTAssertTrue(last.waitForExistence(timeout: 10), "Moving down loads the author's second page")
        let observed = try await RelatedFixture.requests()
        let filter = "authors." + Data("author".utf8).base64EncodedString()
        XCTAssertTrue(observed.contains { $0.path == "/api/authors/author" })
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/items" && $0.query["filter"] == filter && $0.query["page"] == "1" })
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/series" && $0.query["filter"] == filter })
    }

    func testSeriesFollowsServerSequenceAndOpensTheIntendedBook() async throws {
        searchAndOpen("saga", result: "search.series.series-saga")
        XCTAssertTrue(app.staticTexts["series-name"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(label("series-name"), "The Tomorrow Saga")
        XCTAssertEqual(label("series-description"), "Read in order: each story picks up where the last one ends.")
        let finished = try await RelatedFixture.finished("series-saga")
        XCTAssertEqual(label("series-progress"), "4 books · \(finished) finished")
        let order = ["book-5", "book-2", "book-9", "book-1"].map { app.buttons["series-book.\($0)"] }
        XCTAssertTrue(order[3].waitForExistence(timeout: 10))
        XCTAssertEqual(order.map { $0.frame.minX }, order.map { $0.frame.minX }.sorted(), "Books follow the server's sequence order")
        XCTAssertEqual(["book-5", "book-2", "book-9", "book-1"].map { label("series-sequence.\($0)") }, ["Book 1", "Book 2", "Book 2.5", "Book 10"])
        capture("series")
        select(order[2])
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "Stories for Tomorrow 10")
        let observed = try await RelatedFixture.requests()
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/series/series-saga" && $0.query["include"] == "progress" })
        XCTAssertFalse(observed.contains { $0.path.hasPrefix("/api/series/") }, "Series details come from the library the books are listed from")
        XCTAssertTrue(observed.contains { $0.path == "/api/libraries/books/items" && $0.query["filter"] == "series." + Data("series-saga".utf8).base64EncodedString() && $0.query["sort"] == "sequence" })
    }

    func testBookDetailsLeadToItsSeriesAndAuthor() {
        signIn()
        waitForHome()
        tab("Audiobooks")
        select(app.buttons["item-book-2"])
        let series = app.buttons["detail-series.series-saga"]
        XCTAssertTrue(series.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(series.label, "The Tomorrow Saga, book 2")
        select(series)
        XCTAssertTrue(app.staticTexts["series-name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["series-book.book-2"].waitForExistence(timeout: 10))
        remote.press(.menu)
        let author = app.buttons["detail-author.author"]
        XCTAssertTrue(author.waitForExistence(timeout: 10))
        select(author)
        XCTAssertTrue(app.staticTexts["author-name"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["detail-series.series-saga"].waitForExistence(timeout: 10), "Back returns to the details that opened the author")
    }

    func testSeriesFailureRecoversWithRetry() async throws {
        try await RelatedFixture.configure(fail: "series")
        searchAndOpen("saga", result: "search.series.series-saga")
        let retry = app.buttons["retry-related"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["related-error"].exists)
        select(retry)
        XCTAssertTrue(app.buttons["series-book.book-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(label("series-name"), "The Tomorrow Saga")
    }
}

enum RelatedFixture {
    struct Request: Decodable { let path: String; let query: [String: String] }
    private struct Observed: Decodable { let requests: [Request]; let finished: [String: Int] }

    static func configure(fail: String?) async throws {
        var request = URLRequest(url: URL(string: TVJourney.fixture + "/__related__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fail": fail.map { $0 as Any } ?? NSNull()])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    static func requests() async throws -> [Request] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: TVJourney.fixture + "/__related__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data).requests
    }

    /// How many books of the series the server now counts as finished.
    static func finished(_ series: String) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: TVJourney.fixture + "/__related__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data).finished[series] ?? -1
    }
}
