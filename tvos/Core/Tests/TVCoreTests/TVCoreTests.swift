import XCTest
@testable import TVCore

final class TVCoreTests: XCTestCase {
    func testServerURLPreservesReverseProxyPathAndEncodesQuery() throws {
        let server = try ServerAddress(" https://books.example/abs/ ")
        let url = try server.url(path: "/api/libraries/library/items", query: [URLQueryItem(name: "q", value: "A & B")])
        XCTAssertEqual(url.path, "/abs/api/libraries/library/items")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "A & B")
    }

    func testQueryPlusSurvivesFormDecodingForFiltersAndSearch() throws {
        let server = try ServerAddress("https://books.example/abs")
        for value in ["genres.4KC+", "A+B C", "genres.4KC%2B"] {
            let url = try server.url(path: "api/libraries/books/items", query: [URLQueryItem(name: "filter", value: value)])
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
            let encodedValue = try XCTUnwrap(query.split(separator: "=", maxSplits: 1).last)
            let formDecoded = String(encodedValue).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            XCTAssertEqual(formDecoded, value, "Express query decoding must preserve the original filter/search value")
        }
    }

    func testServerRejectsCredentialsAndNonHTTPAddresses() {
        for value in ["file:///tmp/books", "https://user:secret@books.example", "https://books.example?token=secret", "books.example", "https://books.example/#fragment"] {
            XCTAssertThrowsError(try ServerAddress(value))
        }
    }

    func testMediaURLsStayOnServerAndPreserveSubpath() throws {
        let server = try ServerAddress("https://books.example/abs")
        XCTAssertEqual(try server.mediaURL("/api/items/book/file/1").path, "/abs/api/items/book/file/1")
        XCTAssertEqual(try server.mediaURL("https://books.example/abs/api/items/book/file/1").path, "/abs/api/items/book/file/1")
        XCTAssertThrowsError(try server.mediaURL("https://other.example/file"))
        XCTAssertThrowsError(try server.mediaURL("//other.example/file"))
        XCTAssertThrowsError(try server.mediaURL("http://books.example/file"))
    }

    func testMultiFileResumeAndSeekingAcrossTrackBoundaries() throws {
        let session = try JSONDecoder().decode(PlaybackSession.self, from: Data(Self.session.utf8))
        XCTAssertEqual(session.position(at: 150)?.trackIndex, 1)
        XCTAssertEqual(session.position(at: 150)?.localTime, 50)
        XCTAssertEqual(session.position(at: 100)?.trackIndex, 1)
        XCTAssertEqual(session.position(at: -10)?.localTime, 0)
        XCTAssertEqual(session.position(at: 900)?.localTime, 200)
        XCTAssertEqual(session.position(at: .nan)?.localTime, 0)
    }

    func testLoginSupportsModernAndLegacyTokens() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(AuthResponse.self, from: Data(#"{"user":{"token":"old"}}"#.utf8))
        let modern = try decoder.decode(AuthResponse.self, from: Data(#"{"user":{"accessToken":"new","refreshToken":"refresh","token":"old"}}"#.utf8))
        XCTAssertEqual(legacy.user.bearerToken, "old")
        XCTAssertEqual(modern.user.bearerToken, "new")
        XCTAssertEqual(modern.user.refreshToken, "refresh")
    }

    func testLibraryItemsDecodeBothFullAndMinifiedAuthorMetadata() throws {
        let decoder = JSONDecoder()
        let full = try decoder.decode(LibraryItem.self, from: Data(#"{"id":"1","mediaType":"book","media":{"metadata":{"title":"Book","authors":[{"name":"Writer"}]}}}"#.utf8))
        let mini = try decoder.decode(LibraryItem.self, from: Data(#"{"id":"2","mediaType":"book","media":{"metadata":{"title":"Book","authorName":"Writer"}}}"#.utf8))
        XCTAssertEqual(full.author, "Writer")
        XCTAssertEqual(mini.author, "Writer")
    }

    @MainActor
    func testExpiredTokenRefreshesAndRetriesWithoutDroppingRefreshToken() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example/abs", accessToken: "expired", refreshToken: "refresh")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = APIClient(store: store, session: http)
        MockURLProtocol.handler = { request in
            if request.url?.path == "/abs/auth/refresh" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-refresh-token"), "refresh")
                return (200, #"{"user":{"accessToken":"fresh"}}"#)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired" { return (401, "") }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
            return (200, #"{"libraries":[{"id":"books","name":"Books","mediaType":"book"}]}"#)
        }
        let libraries = try await api.libraries()
        XCTAssertEqual(libraries.first?.id, "books")
        XCTAssertEqual(store.value?.accessToken, "fresh")
        XCTAssertEqual(store.value?.refreshToken, "refresh")
        MockURLProtocol.handler = nil
        http.invalidateAndCancel()
    }

    @MainActor
    func testAudioTokenRefreshesBeforeLoadingAnExpiredJWT() async throws {
        let store = MemoryCredentials()
        let expiredPayload = Data(#"{"exp":1}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        store.value = Credentials(server: "https://books.example", accessToken: "header.\(expiredPayload).signature", refreshToken: "refresh")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = APIClient(store: store, session: http)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/refresh")
            return (200, #"{"user":{"accessToken":"fresh","refreshToken":"rotated"}}"#)
        }
        let token = try await api.validToken()
        XCTAssertEqual(token, "fresh")
        XCTAssertEqual(store.value?.refreshToken, "rotated")
        MockURLProtocol.handler = nil
        http.invalidateAndCancel()
    }

    @MainActor
    func testUnauthorizedLegacyTokenRequiresSignInAndDoesNotLoop() async throws {
        let store = MemoryCredentials()
        store.value = Credentials(server: "https://books.example", accessToken: "old", refreshToken: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = APIClient(store: store, session: http)
        MockURLProtocol.handler = { _ in (401, "") }
        do {
            _ = try await api.libraries()
            XCTFail("Unauthorized requests must fail")
        } catch {
            XCTAssertEqual(error as? APIError, .signInRequired)
        }
        MockURLProtocol.handler = nil
        http.invalidateAndCancel()
    }

    static let session = #"{"id":"session","currentTime":150,"duration":300,"audioTracks":[{"contentUrl":"/track/0","startOffset":0,"duration":100},{"contentUrl":"/track/1","startOffset":100,"duration":200}]}"#
}

@MainActor
final class MemoryCredentials: CredentialStore {
    var value: Credentials?
    func load() throws -> Credentials? { value }
    func save(_ credentials: Credentials) throws { value = credentials }
    func clear() throws { value = nil }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, body) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
