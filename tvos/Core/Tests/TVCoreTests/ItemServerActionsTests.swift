import XCTest
@testable import TVCore

/// Item RSS feed and send-ebook actions against the 2.30 routes: `POST /api/authorize`, `GET /api/items/:id?include=rssfeed`,
/// `POST /api/feeds/item/:id/open`, `POST /api/feeds/:id/close` and `POST /api/emails/send-ebook-to-device`.
@MainActor final class ItemServerActionsTests: XCTestCase {
    private struct Seen { let method: String; let host: String; let path: String; let query: [String: String]; let body: [String: Any]? }
    private var http: URLSession!
    private var api: APIClient!
    private var seen: [Seen] = []

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

    private static let audio = #""tracks":[{"index":1,"duration":8}]"#
    private static let ebook = #""ebookFile":{"ino":"pdf","ebookFormat":"pdf","metadata":{"filename":"stories.pdf"}}"#
    private static let openFeed = #"{"id":"saga-feed","entityType":"libraryItem","entityId":"book-1","feedUrl":"/feed/saga-feed","meta":{"title":"Stories","description":null,"preventIndexing":true,"ownerName":null,"ownerEmail":null}}"#

    /// Serves a 2.30 account and item; `respond` may answer any request first.
    private func serve(user: String = "a", type: String = "admin", devices: String? = #"[{"name":"Kindle","email":"kindle@example.invalid","availabilityOption":"userOrUp","users":[]}]"#,
                       media: String = audio, feed: String? = "null", respond: ((Seen) -> (Int, String)?)? = nil) {
        MockURLProtocol.handler = { [unowned self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let body = Self.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let entry = Seen(method: request.httpMethod ?? "GET", host: components.host ?? "", path: components.path,
                             query: Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 }), body: body)
            seen.append(entry)
            if let answer = respond?(entry) { return answer }
            switch (entry.method, entry.path) {
            case ("POST", "/abs/api/authorize"):
                return (200, #"{"user":{"id":"\#(user)","username":"\#(user)","type":"\#(type)"},"userDefaultLibraryId":"books","serverSettings":{}\#(devices.map { #","ereaderDevices":\#($0)"# } ?? "")}"#)
            case ("GET", "/abs/api/items/book-1"):
                return (200, #"{"id":"book-1","libraryId":"books","mediaType":"book","media":{"metadata":{"title":"Stories"},\#(media)}\#(feed.map { #","rssFeed":\#($0)"# } ?? "")}"#)
            default: return (404, "")
            }
        }
    }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
        return data
    }

    private func signIn(_ server: String, user: String) throws {
        try api.completeBrowserLogin(server: server, response: Data(#"{"user":{"id":"\#(user)","username":"\#(user)","accessToken":"token-\#(user)"}}"#.utf8))
    }

    private var mutations: [Seen] { seen.filter { $0.method == "POST" && $0.path != "/abs/api/authorize" } }

    func testLoadingReadsTheAccountDevicesAndTheItemsFeed() async throws {
        serve(feed: Self.openFeed)
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertNil(actions.error)
        XCTAssertTrue(actions.loaded)
        XCTAssertEqual(actions.feed?.id, "saga-feed")
        XCTAssertEqual(actions.devices.map(\.name), ["Kindle"])
        let item = try XCTUnwrap(seen.first { $0.path == "/abs/api/items/book-1" })
        XCTAssertEqual(item.query["expanded"], "1")
        XCTAssertEqual(item.query["include"], "rssfeed")
        XCTAssertTrue(seen.contains { $0.method == "POST" && $0.path == "/abs/api/authorize" })
        XCTAssertEqual(actions.feedURL(try XCTUnwrap(actions.feed)), "https://books.example/abs/feed/saga-feed", "The feed path is relative to the server address, as the baseline shows it")
    }

    func testAnAdminOpensAFeedWithTheBaselinePayload() async throws {
        serve { entry in entry.path == "/abs/api/feeds/item/book-1/open" ? (200, #"{"feed":\#(Self.openFeed)}"#) : nil }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertTrue(actions.showsFeed)
        XCTAssertTrue(actions.canManageFeed)
        XCTAssertNil(actions.feed)
        await actions.openFeed(slug: "saga-feed", preventIndexing: false, ownerName: "Owner", ownerEmail: "")
        XCTAssertNil(actions.error)
        XCTAssertEqual(actions.feed?.feedUrl, "/feed/saga-feed")
        XCTAssertNil(actions.activity)
        let open = try XCTUnwrap(mutations.first)
        XCTAssertEqual(open.path, "/abs/api/feeds/item/book-1/open")
        XCTAssertEqual(open.body?["serverAddress"] as? String, "https://books.example/abs")
        XCTAssertEqual(open.body?["slug"] as? String, "saga-feed")
        let details = try XCTUnwrap(open.body?["metadataDetails"] as? [String: Any])
        XCTAssertEqual(details["preventIndexing"] as? Bool, false)
        XCTAssertEqual(details["ownerName"] as? String, "Owner")
        XCTAssertEqual(details["ownerEmail"] as? String, "")
    }

    func testAnAdminClosesTheOpenFeed() async throws {
        serve(feed: Self.openFeed) { entry in entry.path == "/abs/api/feeds/saga-feed/close" ? (200, "OK") : nil }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.closeFeed()
        XCTAssertNil(actions.error)
        XCTAssertNil(actions.feed)
        XCTAssertEqual(mutations.map(\.path), ["/abs/api/feeds/saga-feed/close"])
        XCTAssertTrue(actions.showsFeed, "An admin can open it again")
    }

    func testOtherUsersViewAnOpenFeedButNeverOpenOrCloseOne() async throws {
        serve(type: "user", feed: Self.openFeed)
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertTrue(actions.showsFeed)
        XCTAssertFalse(actions.canManageFeed)
        await actions.closeFeed()
        await actions.openFeed(slug: "other", preventIndexing: true, ownerName: "", ownerEmail: "")
        XCTAssertTrue(mutations.isEmpty, "The server allows feed changes to admins only")
        XCTAssertEqual(actions.feed?.id, "saga-feed")
    }

    func testTheFeedActionNeedsAnOpenFeedOrAnAdminWithAudio() async throws {
        serve(type: "user")
        let user = ItemServerActions(api: api, itemID: "book-1")
        await user.load()
        XCTAssertTrue(user.loaded)
        XCTAssertFalse(user.showsFeed, "Without an open feed only admins see the action")

        serve(type: "root", media: #""tracks":[]"#)
        let silent = ItemServerActions(api: api, itemID: "book-1")
        await silent.load()
        XCTAssertFalse(silent.showsFeed, "A feed cannot be opened for an item without audio")
        await silent.openFeed(slug: "book-1", preventIndexing: true, ownerName: "", ownerEmail: "")
        XCTAssertTrue(mutations.isEmpty)

        serve(type: "root")
        let root = ItemServerActions(api: api, itemID: "book-1")
        await root.load()
        XCTAssertTrue(root.showsFeed)
        XCTAssertTrue(root.canManageFeed, "Root is admin or up")
    }

    func testAnInvalidSlugIsRejectedBeforeAnyRequest() async throws {
        serve()
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.openFeed(slug: "My Feed", preventIndexing: true, ownerName: "", ownerEmail: "")
        await actions.openFeed(slug: "", preventIndexing: true, ownerName: "", ownerEmail: "")
        XCTAssertTrue(mutations.isEmpty)
        XCTAssertNotNil(actions.error)
    }

    func testSlugsAreSanitizedLikeTheBaseline() {
        XCTAssertEqual(ItemServerActions.sanitizedSlug("book-1"), "book-1")
        XCTAssertEqual(ItemServerActions.sanitizedSlug("  Évening Tales.Vol.2 "), "evening-tales-vol.2", "Only the first dot becomes a dash")
        XCTAssertEqual(ItemServerActions.sanitizedSlug("Señor / Niño: Part,1"), "senor-nino-part-1")
        XCTAssertEqual(ItemServerActions.sanitizedSlug("a  --  b"), "a-b")
        XCTAssertEqual(ItemServerActions.sanitizedSlug("ok~{x}"), "okx", "Characters past `_` are removed; the baseline range ` -_` keeps the rest of ASCII punctuation")
    }

    func testTheEbookIsSentToAnAccessibleDevice() async throws {
        serve(devices: #"[{"name":"Kindle","email":"kindle@example.invalid"},{"name":"Kobo","email":"kobo@example.invalid"}]"#, media: Self.audio + "," + Self.ebook) { entry in
            entry.path == "/abs/api/emails/send-ebook-to-device" ? (200, "OK") : nil
        }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertTrue(actions.canSendEbook)
        XCTAssertEqual(actions.devices.map(\.name), ["Kindle", "Kobo"])
        await actions.send(to: EReaderDevice(name: "Kobo"))
        XCTAssertNil(actions.error)
        XCTAssertEqual(actions.sent, "Kobo")
        let send = try XCTUnwrap(mutations.first)
        XCTAssertEqual(send.path, "/abs/api/emails/send-ebook-to-device")
        XCTAssertEqual(send.body?["libraryItemId"] as? String, "book-1")
        XCTAssertEqual(send.body?["deviceName"] as? String, "Kobo")
        XCTAssertEqual(send.body?.count, 2)
    }

    func testSendingNeedsAnEbookAndADeviceTheServerListsForTheUser() async throws {
        serve(media: Self.audio)
        let noEbook = ItemServerActions(api: api, itemID: "book-1")
        await noEbook.load()
        XCTAssertFalse(noEbook.canSendEbook)
        await noEbook.send(to: EReaderDevice(name: "Kindle"))

        serve(devices: nil, media: Self.ebook)
        let older = ItemServerActions(api: api, itemID: "book-1")
        await older.load()
        XCTAssertTrue(older.loaded)
        XCTAssertFalse(older.canSendEbook, "No device list means no device the user may use")

        serve(devices: "[]", media: Self.ebook)
        let none = ItemServerActions(api: api, itemID: "book-1")
        await none.load()
        XCTAssertFalse(none.canSendEbook)
        await none.send(to: EReaderDevice(name: "Kindle"))

        serve(media: Self.ebook)
        let listed = ItemServerActions(api: api, itemID: "book-1")
        await listed.load()
        await listed.send(to: EReaderDevice(name: "Someone else's reader"))
        XCTAssertTrue(mutations.isEmpty, "Only devices the server listed for this user are offered")
    }

    func testAFailedActionIsReportedAndCanBeRetried() async throws {
        var failures = 1
        serve(media: Self.ebook) { entry in
            guard entry.path == "/abs/api/emails/send-ebook-to-device" else { return nil }
            if failures > 0 { failures -= 1; return (400, "Failed to send ebook to device") }
            return (200, "OK")
        }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.send(to: EReaderDevice(name: "Kindle"))
        XCTAssertEqual(actions.error as? APIError, .http(400))
        XCTAssertNil(actions.sent)
        XCTAssertNil(actions.activity)
        await actions.send(to: EReaderDevice(name: "Kindle"))
        XCTAssertNil(actions.error)
        XCTAssertEqual(actions.sent, "Kindle")
        XCTAssertEqual(mutations.count, 2)
    }

    func testAFailedLoadIsReportedAndLoadingAgainRecovers() async throws {
        var failures = 1
        serve { entry in
            guard entry.path == "/abs/api/authorize", failures > 0 else { return nil }
            failures -= 1
            return (503, "")
        }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertEqual(actions.error as? APIError, .http(503))
        XCTAssertFalse(actions.loaded)
        XCTAssertFalse(actions.showsFeed)
        await actions.load()
        XCTAssertNil(actions.error)
        XCTAssertTrue(actions.showsFeed)
    }

    func testActionsOpenedForOneSignInNeverRunForAnotherOrTheSameAccountAgain() async throws {
        serve(media: Self.audio + "," + Self.ebook, feed: Self.openFeed)
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        let opened = seen.count

        try signIn("https://other.example/abs", user: "b")
        await actions.load()
        await actions.closeFeed()
        await actions.openFeed(slug: "taken-over", preventIndexing: true, ownerName: "", ownerEmail: "")
        await actions.send(to: EReaderDevice(name: "Kindle"))
        XCTAssertEqual(seen.count, opened, "Nothing goes out for B: \(seen.dropFirst(opened).map { $0.host + $0.path })")

        try signIn("https://books.example/abs", user: "a")
        await actions.load()
        await actions.closeFeed()
        await actions.send(to: EReaderDevice(name: "Kindle"))
        XCTAssertEqual(seen.count, opened, "Signing A in again is a new sign-in, not the one the actions were opened for")
        XCTAssertEqual(actions.feed?.id, "saga-feed")
        XCTAssertNil(actions.sent)
        XCTAssertNil(actions.error)
    }

    func testASignInChangeDuringAnActionDropsItsResult() async throws {
        serve { [unowned self] entry in
            guard entry.path == "/abs/api/feeds/item/book-1/open" else { return nil }
            DispatchQueue.main.sync { MainActor.assumeIsolated { try! self.signIn("https://other.example/abs", user: "b") } }
            return (200, #"{"feed":\#(Self.openFeed)}"#)
        }
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.openFeed(slug: "saga-feed", preventIndexing: true, ownerName: "", ownerEmail: "")
        XCTAssertNil(actions.feed, "A's result is not shown once B signed in")
        XCTAssertNil(actions.error)
        XCTAssertNil(actions.activity)
    }

    func testAnAuthorizationForAnotherUserIsNotShown() async throws {
        serve(user: "z", feed: Self.openFeed)
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertFalse(actions.loaded)
        XCTAssertNil(actions.feed)
        XCTAssertTrue(actions.devices.isEmpty)
    }

    func testAFeedOpenedOrClosedElsewhereReplacesTheItemsFeed() async throws {
        serve(type: "user")
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertFalse(actions.showsFeed)
        actions.feedChanged(try JSONDecoder().decode(RSSFeed.self, from: Data(Self.openFeed.utf8)))
        XCTAssertEqual(actions.feed?.id, "saga-feed")
        XCTAssertTrue(actions.showsFeed, "Anyone sees a feed another client opened, as on the baseline item page")
        actions.feedChanged(nil)
        XCTAssertNil(actions.feed)
        XCTAssertFalse(actions.showsFeed)
    }

    func testAFeedClosedWhileTheItemLoadsIsNotReopenedByTheOlderResponse() async throws {
        var actions: ItemServerActions!
        serve(feed: Self.openFeed) { entry in
            guard entry.path == "/abs/api/items/book-1" else { return nil }
            DispatchQueue.main.sync { MainActor.assumeIsolated { actions.feedChanged(nil) } }
            return nil
        }
        actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        XCTAssertTrue(actions.loaded)
        XCTAssertNil(actions.feed, "The item was read before the feed closed, so its open feed is stale")
    }

    func testAnOpenAnsweredAfterAnotherClientClosedTheFeedKeepsItClosed() async throws {
        var actions: ItemServerActions!
        serve { entry in
            guard entry.path == "/abs/api/feeds/item/book-1/open" else { return nil }
            DispatchQueue.main.sync { MainActor.assumeIsolated { actions.feedChanged(nil) } }
            return (200, #"{"feed":\#(Self.openFeed)}"#)
        }
        actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.openFeed(slug: "saga-feed", preventIndexing: true, ownerName: "", ownerEmail: "")
        XCTAssertNil(actions.feed, "Another client closed the feed after this open reached the server")
        XCTAssertNil(actions.activity)
        XCTAssertNil(actions.error)
        XCTAssertTrue(actions.showsFeed, "An admin can open it again")
    }

    func testACloseAnsweredAfterAnotherClientOpenedAReplacementKeepsTheReplacement() async throws {
        var actions: ItemServerActions!
        let replacement = Self.openFeed.replacingOccurrences(of: "saga-feed", with: "replacement-feed")
        serve(feed: Self.openFeed) { entry in
            guard entry.path == "/abs/api/feeds/saga-feed/close" else { return nil }
            DispatchQueue.main.sync { MainActor.assumeIsolated { actions.feedChanged(try! JSONDecoder().decode(RSSFeed.self, from: Data(replacement.utf8))) } }
            return (200, "OK")
        }
        actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        await actions.closeFeed()
        XCTAssertEqual(actions.feed?.id, "replacement-feed", "Another client opened a new feed after this close reached the server")
        XCTAssertNil(actions.activity)
        XCTAssertNil(actions.error)
    }

    func testAFeedChangeAfterASignInChangeIsIgnored() async throws {
        serve(feed: Self.openFeed)
        let actions = ItemServerActions(api: api, itemID: "book-1")
        await actions.load()
        try signIn("https://books.example/abs", user: "a")
        actions.feedChanged(nil)
        XCTAssertEqual(actions.feed?.id, "saga-feed", "A change received by another sign-in does not belong to these actions")
    }

    func testAPodcastFeedWarnsWhenEpisodesHaveNoPublishedDate() async throws {
        serve(media: #""episodes":[{"id":"e1","pubDate":"Mon, 01 Jan 2024 00:00:00 GMT"},{"id":"e2","pubDate":null}]"#)
        let podcast = ItemServerActions(api: api, itemID: "book-1")
        await podcast.load()
        XCTAssertTrue(podcast.showsFeed, "Podcast episodes are audio for a feed")
        XCTAssertTrue(podcast.hasEpisodesWithoutPubDate)

        serve()
        let book = ItemServerActions(api: api, itemID: "book-1")
        await book.load()
        XCTAssertFalse(book.hasEpisodesWithoutPubDate)
    }
}
