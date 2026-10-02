import XCTest
@testable import TVCore

/// Author and series contracts from the Audiobookshelf 2.30 server source.
final class RelatedAuthorSeriesTests: XCTestCase {
    private func item(_ metadata: String) throws -> TVCore.LibraryItem {
        try JSONDecoder().decode(TVCore.LibraryItem.self, from: Data(#"{"id":"book","mediaType":"book","media":{"metadata":{"title":"A Story",\#(metadata)}}}"#.utf8))
    }

    func testExpandedItemsCarryEverySeriesWithItsSequence() throws {
        let book = try item(#""authors":[{"id":"author","name":"Writer"}],"series":[{"id":"saga","name":"Saga","sequence":"2.5"},{"id":"omnibus","name":"Omnibus","sequence":null}]"#)
        XCTAssertEqual(book.series, [SeriesReference(id: "saga", name: "Saga", sequence: "2.5"), SeriesReference(id: "omnibus", name: "Omnibus", sequence: nil)])
        XCTAssertEqual(book.media.metadata.authors?.first?.id, "author")
    }

    func testItemsKnowTheirLibrarySoRelatedPagesQueryIt() throws {
        let book = try JSONDecoder().decode(TVCore.LibraryItem.self, from: Data(#"{"id":"book","libraryId":"books","mediaType":"book","media":{"metadata":{"title":"A Story"}}}"#.utf8))
        XCTAssertEqual(book.libraryId, "books")
    }

    func testSeriesFilteredItemsCarryOneSeriesObject() throws {
        let book = try item(#""series":{"id":"saga","name":"Saga","sequence":"10"}"#)
        XCTAssertEqual(book.series, [SeriesReference(id: "saga", name: "Saga", sequence: "10")])
    }

    func testUnexpectedSeriesShapesDoNotHideTheBook() throws {
        XCTAssertEqual(try item(#""series":"Saga #1","seriesName":"Saga #1""#).series, [])
        XCTAssertEqual(try item(#""seriesName":"Saga #1""#).media.metadata.seriesName, "Saga #1")
        XCTAssertEqual(try item(#""series":[{"id":"saga","name":"Saga","sequence":3}]"#).series.first?.sequence, "3", "A numeric sequence is kept as the server's text")
    }

    func testAuthorAndSeriesMetadataDecode() throws {
        let author = try JSONDecoder().decode(AuthorDetail.self, from: Data(#"{"id":"author","asin":null,"name":"Writer","description":"Bio","imagePath":"/metadata/authors/author.jpg","libraryId":"books","addedAt":1,"updatedAt":2}"#.utf8))
        XCTAssertEqual(author.name, "Writer")
        XCTAssertEqual(author.description, "Bio")
        XCTAssertTrue(author.hasImage)
        XCTAssertFalse(try JSONDecoder().decode(AuthorDetail.self, from: Data(#"{"id":"a","name":"N","imagePath":null}"#.utf8)).hasImage)
        let series = try JSONDecoder().decode(SeriesDetail.self, from: Data(#"{"id":"saga","name":"Saga","nameIgnorePrefix":"Saga","description":null,"progress":{"libraryItemIds":["a","b"],"libraryItemIdsFinished":["a"],"isFinished":false}}"#.utf8))
        XCTAssertEqual(series.progress?.libraryItemIds.count, 2)
        XCTAssertEqual(series.progress?.libraryItemIdsFinished, ["a"])
        let page = try JSONDecoder().decode(SeriesPage.self, from: Data(#"{"results":[{"id":"saga","name":"Saga","books":[{"id":"b","mediaType":"book","media":{"metadata":{"title":"T"}}}]}],"total":3,"limit":1,"page":0}"#.utf8))
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.results.first?.books?.first?.id, "b")
    }

    @MainActor
    func testRelatedRequestsUseTheServerRoutesAndFilters() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example/abs", accessToken: "token", refreshToken: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = APIClient(store: store, session: http)
        var seen: [URLComponents] = []
        MockURLProtocol.handler = { request in
            seen.append(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!)
            switch request.url!.path {
            case "/abs/api/authors/author": return (200, #"{"id":"author","name":"Writer"}"#)
            case "/abs/api/libraries/books/series/saga": return (200, #"{"id":"saga","name":"Saga"}"#)
            case "/abs/api/libraries/books/series": return (200, #"{"results":[],"total":0}"#)
            case "/abs/api/authors/author/image": return (200, "image")
            default: return (404, "")
            }
        }
        defer { MockURLProtocol.handler = nil; http.invalidateAndCancel() }
        _ = try await api.author(id: "author")
        _ = try await api.series(libraryID: "books", id: "saga")
        _ = try await api.authorSeries(libraryID: "books", authorID: "author", page: 2)
        let image = try await api.authorImageData(authorID: "author", authorization: api.authorizationRevision)
        XCTAssertEqual(image, Data("image".utf8))
        func value(_ name: String, _ components: URLComponents) -> String? { components.queryItems?.first { $0.name == name }?.value }
        XCTAssertEqual(seen.map(\.path), ["/abs/api/authors/author", "/abs/api/libraries/books/series/saga", "/abs/api/libraries/books/series", "/abs/api/authors/author/image"])
        XCTAssertEqual(value("include", seen[1]), "progress")
        XCTAssertEqual(value("filter", seen[2]), "authors." + Data("author".utf8).base64EncodedString())
        XCTAssertEqual(value("sort", seen[2]), "name")
        XCTAssertEqual(value("page", seen[2]), "2")
        XCTAssertNotNil(value("width", seen[3]))
        XCTAssertEqual(APIClient.relatedFilter("series", "s>?"), "series." + Data("s>?".utf8).base64EncodedString(), "Values are base64 for the server's filter decoder")
    }
}
