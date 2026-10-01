import XCTest
@testable import TVCore

/// The author and series pages shared by the TV and mobile apps, against 2.30 response shapes.
@MainActor final class RelatedLoadersTests: XCTestCase {
    private var http: URLSession!
    private var api: APIClient!
    private var seen: [URLComponents] = []

    override func setUp() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example/abs", accessToken: "token", refreshToken: nil)
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
            case "/abs/api/series/saga": return (200, #"{"id":"saga","name":"Saga","description":"In order","progress":{"libraryItemIds":["b5","b2","b9","b1"],"libraryItemIdsFinished":["b5"],"isFinished":false}}"#)
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
        XCTAssertEqual(requests("/abs/api/series/saga").first?["include"], "progress")
    }

    func testAFailedSeriesIsReportedAndLoadingAgainRecovers() async throws {
        var failures = 1
        serve { path, _ in
            switch path {
            case "/abs/api/series/saga":
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
}
