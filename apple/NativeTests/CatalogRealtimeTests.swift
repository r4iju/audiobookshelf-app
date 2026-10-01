import XCTest

/// `CatalogStore` reports failures through the app's connection recovery text; the hostless test target only needs a message.
enum ConnectionStore {
    static func recovery(for error: Error) -> String { String(describing: error) }
}

/// An in-process library of 120 books for two users. A held request is answered from the library as it was when the
/// request arrived, and only delivered when the test releases it, as a slow network would.
final class CatalogServer: URLProtocol {
    static let address = "https://books.example.test/abs"
    private static let lock = NSLock()
    private static var titles: [(id: String, title: String)] = []
    private static var listening: [String: [String]] = [:]
    private static var holding: [String] = []
    private static var held: [String: () -> Void] = [:]

    static func reset() {
        locked {
            titles = (0..<120).map { ("book-\($0)", "Title \($0)") }
            listening = ["user-a": ["book-0"], "user-b": ["book-1"]]
            holding = []; held = [:]
        }
    }
    static func rename(_ id: String, _ title: String) { locked { titles = titles.map { $0.id == id ? ($0.id, title) : $0 } } }
    static func remove(_ id: String) { locked { titles.removeAll { $0.id == id } } }
    static func listen(_ user: String, to id: String) { locked { listening[user, default: []].append(id) } }
    /// Holds the next request whose path and query contain `key`.
    static func hold(_ key: String) { locked { holding.append(key) } }
    static func isHeld(_ key: String) -> Bool { locked { held[key] != nil } }
    static func release(_ key: String) { locked { held.removeValue(forKey: key) }?() }
    static func item(_ id: String, _ title: String) -> [String: Any] {
        ["id": id, "libraryId": "books", "mediaType": "book", "media": ["metadata": ["title": title]]]
    }

    private static func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let target = url.path + "?" + (url.query ?? "")
        let user = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-b" ? "user-b" : "user-a"
        let body = Self.locked { Self.answer(target, user: user) }
        let deliver = { [self] in
            guard let body else { return client!.urlProtocol(self, didFailWithError: URLError(.badURL)) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
            client!.urlProtocolDidFinishLoading(self)
        }
        let key: String? = Self.locked {
            guard let index = Self.holding.firstIndex(where: { target.contains($0) }) else { return nil }
            let key = Self.holding.remove(at: index); Self.held[key] = deliver
            return key
        }
        if key == nil { deliver() }
    }

    private static func answer(_ target: String, user: String) -> Any? {
        let books = titles.map { item($0.id, $0.title) }
        if target.hasPrefix("/abs/api/me?") {
            let progress = (listening[user] ?? []).map { ["id": "progress-\($0)", "libraryItemId": $0, "currentTime": 10, "duration": 20, "progress": 0.5, "isFinished": false] as [String: Any] }
            return ["id": user, "username": user, "type": "user", "mediaProgress": progress, "permissions": [:] as [String: Any], "bookmarks": [] as [Any]]
        }
        if target.hasPrefix("/abs/api/libraries/books/personalized?") {
            let continuing = books.filter { (listening[user] ?? []).contains($0["id"] as! String) }
            return [["id": "continue-listening", "type": "book", "entities": continuing]]
        }
        if target.hasPrefix("/abs/api/libraries/books/items?"), let page = URLComponents(string: target)?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) {
            return ["results": Array(books.dropFirst(page * 60).prefix(60)), "total": books.count]
        }
        return nil
    }
}

@MainActor final class CatalogRealtimeTests: XCTestCase {
    private let credentials = MemoryCredentials()
    private var api: APIClient!
    private var store: CatalogStore!

    override func setUp() async throws {
        CatalogServer.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogServer.self]
        signIn("user-a")
        api = APIClient(store: credentials, session: URLSession(configuration: configuration))
        store = CatalogStore(api: api, library: Library(id: "books", name: "Books", mediaType: "book", folders: nil))
        await store.reload()
        XCTAssertEqual(content?.items.count, 60)
    }

    func testProgressDuringAReconnectionReloadKeepsTheReloadAndReleasesPaging() async throws {
        CatalogServer.hold("page=1")
        let paging = Task { await store.loadMore() }
        try await until { CatalogServer.isHeld("page=1") }
        CatalogServer.rename("book-0", "Changed while disconnected")
        CatalogServer.hold("page=0")
        store.receive(event(.authenticated(resumed: true)))
        try await until { CatalogServer.isHeld("page=0") }
        CatalogServer.listen("user-a", to: "book-5")
        store.receive(event(.progress(itemID: "book-5", episodeID: nil, sessionID: "web")))
        CatalogServer.release("page=1")
        await paging.value
        CatalogServer.release("page=0")
        try await until { self.content?.items.first?.title == "Changed while disconnected" && self.content?.continuing.map(\.id) == ["book-0", "book-5"] }
        XCTAssertEqual(content?.loadingMore, false, "Paging must not stay blocked after the reconnection reload")
        await store.loadMore()
        XCTAssertEqual(content?.items.count, 120)
    }

    func testItemChangesWhileAPageLoadsAreNotUndoneByTheOlderPage() async throws {
        CatalogServer.hold("page=1")
        let paging = Task { await store.loadMore() }
        try await until { CatalogServer.isHeld("page=1") }
        let renamed = try decode(CatalogServer.item("book-1", "Renamed elsewhere"))
        let renamedLater = try decode(CatalogServer.item("book-61", "Renamed on the next page"))
        store.receive(event(.itemsUpdated([renamed, renamedLater])))
        try await until { self.content?.items[1].title == "Renamed elsewhere" }
        CatalogServer.release("page=1")
        await paging.value
        try await until { self.content?.loadingMore == false && self.content?.items.count == 120 }
        XCTAssertEqual(content?.items.first { $0.id == "book-1" }?.title, "Renamed elsewhere", "An older page must not restore stale metadata")
        XCTAssertEqual(content?.items.first { $0.id == "book-61" }?.title, "Renamed on the next page", "A page answered before an update must show the update")
    }

    func testRemovalWhileAPageLoadsDoesNotReturnAndLaterPagesStayComplete() async throws {
        CatalogServer.hold("page=1")
        let paging = Task { await store.loadMore() }
        try await until { CatalogServer.isHeld("page=1") }
        CatalogServer.remove("book-2"); CatalogServer.remove("book-70")
        store.receive(event(.itemRemoved(id: "book-2")))
        store.receive(event(.itemRemoved(id: "book-70")))
        CatalogServer.release("page=1")
        await paging.value
        try await until { self.content?.loadingMore == false && self.content?.items.contains { $0.id == "book-2" } == false }
        while content?.hasMore == true { await store.loadMore() }
        let ids = content?.items.map(\.id) ?? []
        XCTAssertFalse(ids.contains("book-2")); XCTAssertFalse(ids.contains("book-70"))
        XCTAssertEqual(ids.count, 118, "Every remaining book must be listed once the catalog is paged to the end")
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertNil(content?.pageError)
    }

    func testAChangeFromAnEarlierSignInIsNotAppliedAfterSigningInAgain() async throws {
        let earlier = event(.itemRemoved(id: "book-0"))
        try switchAccount("user-b"); try switchAccount("user-a")
        store.receive(earlier)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(content?.items.first?.id, "book-0", "A change received by an earlier sign-in must not touch the current one")
    }

    func testAProgressChangeForTheSameUserIDOnAnotherServerIsNotFetched() async throws {
        let elsewhere = event(.user)
        CatalogServer.listen("user-a", to: "book-9")
        credentials.value = Credentials(server: "https://other.example.test/abs", accessToken: "token-a", refreshToken: nil, userID: "user-a", username: "user-a")
        try api.restoreSavedCredentials()
        store.receive(elsewhere)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(content?.user.mediaProgress.map(\.libraryItemId), ["book-0"], "A change for an equal user ID on another server must not refresh this catalog")
        XCTAssertEqual(content?.continuing.map(\.id), ["book-0"])
    }

    func testAnotherAccountsChangeDoesNotReachACatalogLoadedForTheFirst() async throws {
        try switchAccount("user-b")
        store.receive(event(.itemRemoved(id: "book-0")))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(content?.items.first?.id, "book-0", "A catalog belongs to the account it was loaded for")
    }

    func testRemoteProgressReloadsAVisibleProgressFilteredShelf() async throws {
        store = CatalogStore(api: api, library: Library(id: "books", name: "Books", mediaType: "book", folders: nil), filter: "progress.aW4tcHJvZ3Jlc3M=")
        await store.reload()
        XCTAssertEqual(content?.items.first?.id, "book-0")
        CatalogServer.remove("book-0")
        store.receive(event(.progress(itemID: "book-0", episodeID: nil, sessionID: "web")))
        try await until { self.content?.items.first?.id == "book-1" }
        XCTAssertEqual(content?.loadingMore, false)
    }

    private var content: CatalogStore.Catalog? {
        if case .content(let value) = store.state { return value }
        return nil
    }
    private func event(_ change: RealtimeChange) -> NativeRealtime.Event { NativeRealtime.Event(signIn: api.signIn!, change: change) }
    private func signIn(_ user: String) {
        credentials.value = Credentials(server: CatalogServer.address, accessToken: user == "user-b" ? "token-b" : "token-a", refreshToken: nil, userID: user, username: user)
    }
    private func switchAccount(_ user: String) throws { signIn(user); try api.restoreSavedCredentials() }
    private func decode(_ value: [String: Any]) throws -> LibraryItem {
        try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func until(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "Condition was not reached")
    }
}
