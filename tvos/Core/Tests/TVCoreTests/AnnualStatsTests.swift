import XCTest
@testable import TVCore

/// Payload shapes from Audiobookshelf 2.30.0 `server/utils/queries/userStats.js` and `adminStats.js`.
final class AnnualStatsTests: XCTestCase {
    static let listenerYear = #"{"totalListeningSessions":3,"totalListeningTime":7200,"totalBookListeningTime":5400,"totalPodcastListeningTime":1800,"topAuthors":[{"name":"Writer","time":5400}],"topGenres":[{"genre":"Fantasy","time":5400}],"mostListenedNarrator":{"time":5400,"name":"Reader"},"mostListenedMonth":{"month":2,"time":7200},"numBooksFinished":1,"numBooksListened":2,"longestAudiobookFinished":{"id":"book-1","title":"Long","duration":36000,"finishedAt":1740000000000},"booksWithCovers":["li-2","li-3"],"finishedBooksWithCovers":["li-1"]}"#

    static let serverYear = #"{"numListeningSessions":40,"numBooksAdded":12,"numAuthorsAdded":5,"totalBooksAddedSize":5368709120,"totalBooksAddedDuration":432000,"booksAddedWithCovers":["li-9","li-8"],"totalBooksSize":1099511627776,"totalBooksDuration":8640000.5,"totalListeningTime":90000.25,"numBooks":800,"topAuthors":[{"name":"Writer","time":9000}],"topNarrators":[{"name":"Reader","time":8000}],"topGenres":[{"genre":"Fantasy","time":7000}]}"#

    func testListenerYearKeepsServerCoverOrderAndToleratesServersWithoutCovers() throws {
        let stats = try JSONDecoder().decode(YearListeningStats.self, from: Data(Self.listenerYear.utf8))
        XCTAssertEqual(stats.finishedBooksWithCovers, ["li-1"])
        XCTAssertEqual(stats.booksWithCovers, ["li-2", "li-3"])
        let older = Self.listenerYear.replacingOccurrences(of: #","booksWithCovers":["li-2","li-3"],"finishedBooksWithCovers":["li-1"]"#, with: "")
        let withoutCovers = try JSONDecoder().decode(YearListeningStats.self, from: Data(older.utf8))
        XCTAssertEqual(withoutCovers.booksWithCovers, [])
        XCTAssertEqual(withoutCovers.finishedBooksWithCovers, [])
        XCTAssertEqual(withoutCovers.numBooksFinished, 1)
    }

    func testServerYearDecodesTheAdminPayloadWithEmptySQLTotals() throws {
        let stats = try JSONDecoder().decode(ServerYearStats.self, from: Data(Self.serverYear.utf8))
        XCTAssertEqual(stats.numBooksAdded, 12)
        XCTAssertEqual(stats.totalBooksSize, 1_099_511_627_776)
        XCTAssertEqual(stats.booksAddedWithCovers, ["li-9", "li-8"])
        XCTAssertEqual(stats.topNarrators.first?.name, "Reader")
        // SUM() over no rows yields null, which the server turns into 0; older payloads may still omit or null it.
        let empty = #"{"numListeningSessions":0,"numBooksAdded":0,"numAuthorsAdded":0,"totalBooksAddedSize":0,"totalBooksAddedDuration":0,"booksAddedWithCovers":[],"totalBooksSize":null,"totalBooksDuration":null,"totalListeningTime":0,"numBooks":0,"topAuthors":[],"topNarrators":[],"topGenres":[]}"#
        let zero = try JSONDecoder().decode(ServerYearStats.self, from: Data(empty.utf8))
        XCTAssertEqual(zero.totalBooksSize, 0)
        XCTAssertEqual(zero.totalBooksDuration, 0)
    }

    func testOnlyAdminsAndRootMayRequestServerYear() throws {
        func user(_ type: String?) throws -> CurrentUser {
            let field = type.map { #","type":"\#($0)""# } ?? ""
            return try JSONDecoder().decode(CurrentUser.self, from: Data(#"{"id":"u","username":"n"\#(field),"mediaProgress":[],"permissions":{}}"#.utf8))
        }
        XCTAssertTrue(try user("root").canViewServerYearStats)
        XCTAssertTrue(try user("admin").canViewServerYearStats)
        XCTAssertFalse(try user("user").canViewServerYearStats)
        XCTAssertFalse(try user("guest").canViewServerYearStats)
        XCTAssertFalse(try user(nil).canViewServerYearStats)
    }

    @MainActor
    func testServerYearUsesTheAdminRouteWithBearerAndSurfacesForbidden() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example/abs", accessToken: "token", refreshToken: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = APIClient(store: store, session: http)
        var paths: [String] = []
        MockURLProtocol.handler = { request in
            paths.append(request.url?.path ?? "")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return request.url?.path == "/abs/api/stats/year/2025" ? (200, Self.serverYear) : (403, "Forbidden")
        }
        let stats = try await api.serverYearStats(2025)
        XCTAssertEqual(stats.numAuthorsAdded, 5)
        do {
            _ = try await api.serverYearStats(2024)
            XCTFail("A forbidden server year must not decode")
        } catch {
            XCTAssertEqual(error as? APIError, .http(403))
        }
        do {
            _ = try await api.serverYearStats(1999)
            XCTFail("Years the server rejects must not be requested")
        } catch {}
        XCTAssertEqual(paths, ["/abs/api/stats/year/2025", "/abs/api/stats/year/2024"])
        MockURLProtocol.handler = nil
        http.invalidateAndCancel()
    }
}
