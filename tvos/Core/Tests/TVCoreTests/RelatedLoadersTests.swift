import XCTest
@testable import TVCore

/// The author and series pages shared by the TV and mobile apps, against 2.30 response shapes.
@MainActor final class RelatedLoadersTests: XCTestCase {
    private var http: URLSession!
    private var api: APIClient!
    private var seen: [URLComponents] = []

    override func setUp() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example/abs", accessToken: "token", refreshToken: nil, userID: "a", username: "a")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        http = URLSession(configuration: configuration)
        api = APIClient(store: store, session: http)
        seen = []
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        http.invalidateAndCancel()
    }

    private func serve(_ respond: @escaping (String, [String: String]) -> (Int, String)) {
        MockURLProtocol.handler = { [unowned self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            seen.append(components)
            return respond(components.path, Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 }))
        }
    }

    private func signIn(_ server: String, user: String) throws {
        try api.completeBrowserLogin(server: server, response: Data(#"{"user":{"id":"\#(user)","username":"\#(user)","accessToken":"token-\#(user)"}}"#.utf8))
    }

    /// Any server answers like the first one, so only the pin can keep another sign-in's requests from succeeding.
    private func serveAuthorEverywhere(seriesTotal: Int = 1) {
        serve { path, query in
            switch path {
            case "/abs/api/authors/author": return (200, #"{"id":"author","name":"Writer","imagePath":"/metadata/authors/author.jpg"}"#)
            case "/abs/api/authors/author/image": return (200, "png")
            case "/abs/api/libraries/books/series": return (200, #"{"results":[{"id":"saga","name":"Saga"}],"total":\#(seriesTotal)}"#)
            case "/abs/api/libraries/books/items":
                return query["page"] == "0" ? (200, #"{"results":[\#(Self.book("b0")),\#(Self.book("b1"))],"total":3}"#) : (200, #"{"results":[\#(Self.book("b2"))],"total":3}"#)
            case "/abs/api/libraries/books/series/saga": return (200, #"{"id":"saga","name":"Saga"}"#)
            default: return (404, "")
            }
        }
    }

    private static func book(_ id: String, series: String? = nil) -> String {
        #"{"id":"\#(id)","libraryId":"books","mediaType":"book","media":{"metadata":{"title":"Title \#(id)"\#(series.map { #","series":{"id":"saga","name":"Saga","sequence":"\#($0)"}"# } ?? "")}}}"#
    }

    private func requests(_ path: String) -> [[String: String]] {
        seen.filter { $0.path == path }.map { Dictionary(($0.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 }) }
    }

    func testAuthorLoadsBioSeriesImageAndEveryPageOfBooks() async throws {
        serve { path, query in
            switch path {
            case "/abs/api/authors/author": return (200, #"{"id":"author","name":"Writer","description":"Bio","imagePath":"/metadata/authors/author.jpg"}"#)
            case "/abs/api/authors/author/image": return (200, "png")
            case "/abs/api/libraries/books/series": return (200, #"{"results":[{"id":"saga","name":"Saga","books":[\#(Self.book("b1"))]}],"total":1}"#)
            case "/abs/api/libraries/books/items":
                return query["page"] == "0" ? (200, #"{"results":[\#(Self.book("b0")),\#(Self.book("b1"))],"total":3}"#) : (200, #"{"results":[\#(Self.book("b2"))],"total":3}"#)
            default: return (404, "")
            }
        }
        let author = RelatedAuthor(api: api, id: "author", libraryID: "books")
        await author.load()
        XCTAssertNil(author.error)
        XCTAssertEqual(author.author?.description, "Bio")
        XCTAssertEqual(author.series.map(\.id), ["saga"])
        XCTAssertEqual(author.imageData, Data("png".utf8))
        XCTAssertEqual(author.books.items.map(\.id), ["b0", "b1"])
        XCTAssertEqual(author.books.total, 3)
        await author.books.loadMore(after: author.books.items[1])
        XCTAssertEqual(author.books.items.map(\.id), ["b0", "b1", "b2"])
        XCTAssertFalse(author.books.hasMore)
        await author.books.loadMore(after: author.books.items[2])
        let filter = "authors." + Data("author".utf8).base64EncodedString()
        XCTAssertEqual(requests("/abs/api/libraries/books/items").map { $0["page"] }, ["0", "1"], "Stops once every title is loaded")
        XCTAssertEqual(Set(requests("/abs/api/libraries/books/items").map { $0["filter"] }), [filter])
        XCTAssertEqual(requests("/abs/api/libraries/books/series").first?["filter"], filter)
    }

    func testAnAuthorWithoutAnImageDoesNotRequestOne() async throws {
        serve { path, _ in
            switch path {
            case "/abs/api/authors/author": return (200, #"{"id":"author","name":"Writer","imagePath":null}"#)
            case "/abs/api/libraries/books/series", "/abs/api/libraries/books/items": return (200, #"{"results":[],"total":0}"#)
            default: return (404, "")
            }
        }
        let author = RelatedAuthor(api: api, id: "author", libraryID: "books")
        await author.load()
        XCTAssertNil(author.error)
        XCTAssertNil(author.imageData)
        XCTAssertFalse(seen.contains { $0.path.hasSuffix("/image") })
    }

    func testSeriesKeepsTheServerSequenceOrderAndProgress() async throws {
        serve { path, _ in
            switch path {
            case "/abs/api/libraries/books/series/saga": return (200, #"{"id":"saga","name":"Saga","description":"In order","progress":{"libraryItemIds":["b5","b2","b9","b1"],"libraryItemIdsFinished":["b5"],"isFinished":false}}"#)
            case "/abs/api/libraries/books/items":
                return (200, #"{"results":[\#(Self.book("b5", series: "1")),\#(Self.book("b2", series: "2")),\#(Self.book("b9", series: "2.5")),\#(Self.book("b1", series: "10"))],"total":4}"#)
            default: return (404, "")
            }
        }
        let series = RelatedSeries(api: api, id: "saga", libraryID: "books")
        await series.load()
        XCTAssertNil(series.error)
        XCTAssertEqual(series.series?.description, "In order")
        XCTAssertEqual(series.books.items.map(\.id), ["b5", "b2", "b9", "b1"], "The server's sequence order is kept, not re-sorted by title or as text")
        XCTAssertEqual(series.books.items.map { series.sequence(of: $0) }, ["1", "2", "2.5", "10"])
        XCTAssertEqual(series.series?.progress?.libraryItemIdsFinished, ["b5"])
        XCTAssertEqual(series.summary, "4 books · 1 finished")
        let query = try XCTUnwrap(requests("/abs/api/libraries/books/items").first)
        XCTAssertEqual(query["sort"], "sequence")
        XCTAssertEqual(query["filter"], "series." + Data("saga".utf8).base64EncodedString())
        XCTAssertEqual(requests("/abs/api/libraries/books/series/saga").first?["include"], "progress", "Series span libraries, so details and progress come from the library the books are listed from")
        XCTAssertTrue(requests("/abs/api/series/saga").isEmpty)
    }

    func testAFailedSeriesIsReportedAndLoadingAgainRecovers() async throws {
        var failures = 1
        serve { path, _ in
            switch path {
            case "/abs/api/libraries/books/series/saga":
                if failures > 0 { failures -= 1; return (503, "") }
                return (200, #"{"id":"saga","name":"Saga"}"#)
            case "/abs/api/libraries/books/items": return (200, #"{"results":[\#(Self.book("b1", series: "1"))],"total":1}"#)
            default: return (404, "")
            }
        }
        let series = RelatedSeries(api: api, id: "saga", libraryID: "books")
        await series.load()
        XCTAssertEqual(series.error as? APIError, .http(503))
        XCTAssertNil(series.series)
        await series.load()
        XCTAssertNil(series.error)
        XCTAssertEqual(series.series?.name, "Saga")
        XCTAssertEqual(series.summary, "1 book", "Without the server's progress only the count is known")
        XCTAssertEqual(series.books.items.map(\.id), ["b1"])
    }

    func testAnAuthorWithMoreSeriesThanOnePageShowsThemAll() async throws {
        let names = (0..<53).map { String(format: "s%02d", $0) }
        serve { path, query in
            switch path {
            case "/abs/api/authors/author": return (200, #"{"id":"author","name":"Writer"}"#)
            case "/abs/api/libraries/books/series":
                let limit = Int(query["limit"] ?? "") ?? 0, page = Int(query["page"] ?? "") ?? 0
                let window = names.dropFirst(page * limit).prefix(limit).map { #"{"id":"\#($0)","name":"\#($0)"}"# }
                return (200, #"{"results":[\#(window.joined(separator: ","))],"total":\#(names.count),"limit":\#(limit),"page":\#(page)}"#)
            case "/abs/api/libraries/books/items": return (200, #"{"results":[],"total":0}"#)
            default: return (404, "")
            }
        }
        let author = RelatedAuthor(api: api, id: "author", libraryID: "books")
        await author.load()
        XCTAssertNil(author.error)
        XCTAssertEqual(author.series.map(\.id), names, "Every series the server totals is listed, in its name order")
    }

    func testAnAuthorPageOpenedForOneSignInNeverRequestsOrShowsAnothers() async throws {
        serveAuthorEverywhere()
        let author = RelatedAuthor(api: api, id: "author", libraryID: "books")
        await author.load()
        XCTAssertEqual(author.books.items.map(\.id), ["b0", "b1"])
        let opened = seen.count

        try signIn("https://other.example/abs", user: "b")
        await author.books.loadMore(after: author.books.items[1])
        await author.load()
        XCTAssertEqual(seen.count, opened, "No later page, detail or image goes out for B: \(seen.dropFirst(opened).map(\.string))")
        XCTAssertEqual(author.books.items.map(\.id), ["b0", "b1"], "B's pages are never appended to A's")

        try signIn("https://books.example/abs", user: "a")
        await author.books.loadMore(after: author.books.items[1])
        await author.load()
        XCTAssertEqual(seen.count, opened, "Signing A in again is a new sign-in, not the one the page was opened for")
        XCTAssertEqual(author.books.items.map(\.id), ["b0", "b1"])
        XCTAssertNil(author.error)
    }

    func testAnAuthorImageIsOnlyRequestedForTheSignInThePageOpenedWith() async throws {
        serveAuthorEverywhere()
        MockURLProtocol.handler = { [unowned self, handler = MockURLProtocol.handler!] request in
            if request.url!.path == "/abs/api/authors/author" { seen.append(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!); return (503, "") }
            return handler(request)
        }
        let author = RelatedAuthor(api: api, id: "author", libraryID: "books")
        await author.load()
        XCTAssertEqual(author.error as? APIError, .http(503))
        serveAuthorEverywhere()
        try signIn("https://other.example/abs", user: "b")
        await author.load()
        XCTAssertFalse(seen.contains { $0.host == "other.example" }, "Retrying under B requests nothing: \(seen.filter { $0.host == "other.example" }.map(\.string))")
        XCTAssertNil(author.imageData)
        XCTAssertNil(author.author)
    }

    func testASeriesPageOpenedForOneSignInNeverRequestsOrShowsAnothers() async throws {
        serveAuthorEverywhere()
        let series = RelatedSeries(api: api, id: "saga", libraryID: "books")
        try signIn("https://other.example/abs", user: "b")
        try signIn("https://books.example/abs", user: "a")
        await series.load()
        XCTAssertTrue(seen.isEmpty, "A page opened before A signed in again loads nothing: \(seen.map(\.string))")
        XCTAssertNil(series.series)
        XCTAssertTrue(series.books.items.isEmpty)
    }
}
