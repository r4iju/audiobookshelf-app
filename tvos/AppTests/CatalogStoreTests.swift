import XCTest
@testable import AudiobookshelfTV

final class CatalogStoreTests: XCTestCase {
    private func response(_ json: String) throws -> SearchResponse {
        try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
    }

    private static let podcast = #""id":"podcast","mediaType":"podcast","media":{"metadata":{"title":"Evening Stories"}}"#
    private static func episode(_ id: String) -> String {
        #"{"libraryItem":{\#(podcast),"recentEpisode":{"id":"\#(id)","title":"Episode \#(id)"}}}"#
    }

    func testSearchKeepsEveryEpisodeMatchAlongsideItsPodcast() throws {
        let podcasts = try response(#"{"podcast":[{"libraryItem":{\#(Self.podcast)}}],"episodes":[\#(Self.episode("one")),\#(Self.episode("two"))]}"#)
        let results = CatalogStore.merge([podcasts])
        XCTAssertEqual(results.map(\.episodeID), [nil, "one", "two"])
        XCTAssertEqual(Set(results.map(\.id)).count, 3)
        XCTAssertEqual(results.map(\.route), [.item(results[0].item), .episode(results[1].item, episodeID: "one"), .episode(results[2].item, episodeID: "two")])
    }

    func testSearchDropsTheSameMatchFromAnotherLibraryOnly() throws {
        let first = try response(#"{"episodes":[\#(Self.episode("one"))]}"#)
        let again = try response(#"{"episodes":[\#(Self.episode("one")),\#(Self.episode("two"))]}"#)
        XCTAssertEqual(CatalogStore.merge([first, again]).map(\.episodeID), ["one", "two"])
    }

    func testSearchKeepsAuthorsAndSeriesWithTheLibraryThatFoundThem() throws {
        let books = try response(#"{"authors":[{"id":"author","name":"Writer"}],"series":[{"series":{"id":"saga","name":"Saga"},"books":[]}]}"#)
        let stories = try response(#"{"authors":[{"id":"author","name":"Writer"},{"id":"poet","name":"Poet"}]}"#)
        let related = CatalogStore.related([(libraryID: "books", response: books), (libraryID: "stories", response: stories)])
        XCTAssertEqual(related, [.author(RelatedLink(id: "author", name: "Writer", libraryID: "books")),
                                 .author(RelatedLink(id: "poet", name: "Poet", libraryID: "stories")),
                                 .series(RelatedLink(id: "saga", name: "Saga", libraryID: "books"))])
    }

    func testOnlyAnAbsentCoverIsRemembered() {
        XCTAssertTrue(CatalogStore.coverIsAbsent(after: APIError.http(404)))
        XCTAssertFalse(CatalogStore.coverIsAbsent(after: APIError.http(503)))
        XCTAssertFalse(CatalogStore.coverIsAbsent(after: APIError.http(500)))
        XCTAssertFalse(CatalogStore.coverIsAbsent(after: APIError.http(429)))
        XCTAssertFalse(CatalogStore.coverIsAbsent(after: URLError(.timedOut)))
        XCTAssertFalse(CatalogStore.coverIsAbsent(after: CancellationError()))
    }
}
