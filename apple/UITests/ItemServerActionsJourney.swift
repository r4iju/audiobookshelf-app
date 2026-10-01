import XCTest

/// Item RSS feed and send-ebook actions from book details, against apple/scripts/item_actions_fixture.py on 27765,
/// which apple/scripts/verify-item-actions.sh starts. Feeds live in the fixture's memory and no email is sent.
@MainActor final class ItemServerActionsJourney: NativeJourney {
    static let fixture = "http://127.0.0.1:27765/abs"

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ABS_ITEM_ACTIONS_QA"] == "1", "Run apple/scripts/verify-item-actions.sh, which starts the item actions fixture on 27765.")
    }

    private func openBook(_ id: String, configure options: [String: Any]) async throws -> XCUIApplication {
        try await ItemActionsFixture.configure(options)
        connectSelectAndRestore(serverURL: Self.fixture, verifyRestoration: false)
        let app = XCUIApplication()
        let book = app.buttons["book-" + id]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        if element.waitForExistence(timeout: timeout), element.isHittable { return true }
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists
    }

    private func waitFor(_ element: XCUIElement, label: String) async {
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)], timeout: 10)
    }

    func testAnAdminOpensCopiesAndClosesTheItemsFeed() async throws {
        let app = try await openBook("book-0", configure: ["role": "admin"])
        let feed = app.buttons["item-rss-feed"]
        XCTAssertTrue(reveal(feed, in: app), app.debugDescription)
        XCTAssertEqual(feed.label, "Open RSS feed")
        feed.tap()

        let slug = app.textFields["rss-slug"]
        XCTAssertTrue(slug.waitForExistence(timeout: 10))
        XCTAssertEqual(slug.value as? String, "book-0", "The slug starts as the item id, like the baseline")
        slug.tap()
        slug.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Evening.Feed 1")
        app.buttons["rss-open"].tap()
        XCTAssertTrue(app.staticTexts["rss-slug-adjusted"].waitForExistence(timeout: 5), "An unsanitized slug is corrected and not sent")
        XCTAssertEqual(slug.value as? String, "evening-feed-1")
        var observed = try await ItemActionsFixture.observations()
        XCTAssertFalse(observed.requests.contains { $0.path.hasPrefix("/api/feeds/") })

        let owner = app.textFields["rss-owner-name"]
        owner.tap()
        owner.typeText("QA Owner")
        app.buttons["rss-open"].tap()
        let url = app.staticTexts["rss-feed-url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(url.label, Self.fixture + "/feed/evening-feed-1")
        XCTAssertEqual(app.staticTexts["rss-owner-name"].label, "QA Owner")
        XCTAssertEqual(app.staticTexts["rss-prevent-indexing"].label, "Yes")
        app.buttons["rss-copy"].tap()
        await waitFor(app.buttons["rss-copy"], label: "Copied")
        capture("item-rss-open-admin")

        observed = try await ItemActionsFixture.observations()
        let open = try XCTUnwrap(observed.requests.first { $0.path == "/api/feeds/item/book-0/open" })
        XCTAssertEqual(open.body?["serverAddress"] as? String, Self.fixture)
        XCTAssertEqual(open.body?["slug"] as? String, "evening-feed-1")
        let details = try XCTUnwrap(open.body?["metadataDetails"] as? [String: Any])
        XCTAssertEqual(details["preventIndexing"] as? Bool, true)
        XCTAssertEqual(details["ownerName"] as? String, "QA Owner")
        XCTAssertEqual(details["ownerEmail"] as? String, "")
        XCTAssertEqual(observed.feeds.map(\.id), ["evening-feed-1"])

        app.buttons["rss-close"].tap()
        await waitFor(feed, label: "Open RSS feed")
        observed = try await ItemActionsFixture.observations()
        XCTAssertTrue(observed.requests.contains { $0.method == "POST" && $0.path == "/api/feeds/evening-feed-1/close" })
        XCTAssertTrue(observed.feeds.isEmpty)
    }

    func testOtherUsersViewAnOpenFeedButCannotManageFeeds() async throws {
        let app = try await openBook("book-0", configure: ["role": "user", "feed": true, "ebook": false])
        let feed = app.buttons["item-rss-feed"]
        XCTAssertTrue(reveal(feed, in: app), app.debugDescription)
        XCTAssertEqual(feed.label, "RSS feed")
        XCTAssertFalse(app.buttons["send-ebook"].exists, "No ebook, no send action")
        feed.tap()
        let url = app.staticTexts["rss-feed-url"]
        XCTAssertTrue(url.waitForExistence(timeout: 10))
        XCTAssertEqual(url.label, Self.fixture + "/feed/qa-feed")
        XCTAssertEqual(app.staticTexts["rss-owner-name"].label, "QA Owner")
        XCTAssertFalse(app.buttons["rss-close"].exists)
        XCTAssertFalse(app.buttons["rss-open"].exists)
        capture("item-rss-view-user")
        app.buttons["rss-done"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let other = app.buttons["book-book-1"]
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        other.tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 10))
        try await ItemActionsFixture.waitForLoad(of: "book-1")
        XCTAssertFalse(app.buttons["item-rss-feed"].waitForExistence(timeout: 3), "Without an open feed only admins see the action")
        let observed = try await ItemActionsFixture.observations()
        XCTAssertFalse(observed.requests.contains { $0.method == "POST" && $0.path.hasPrefix("/api/feeds/") })
    }

    func testTheEbookIsSentToADeviceTheServerAllowsForTheUser() async throws {
        let app = try await openBook("book-0", configure: ["role": "user"])
        let send = app.buttons["send-ebook"]
        XCTAssertTrue(reveal(send, in: app), app.debugDescription)
        XCTAssertFalse(app.buttons["item-rss-feed"].exists, "No open feed and not an admin")
        send.tap()
        XCTAssertTrue(app.buttons["Shared Kindle"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Reading Tablet"].exists)
        XCTAssertFalse(app.buttons["Admin Reader"].exists, "Admin-only devices are not listed for a user")
        XCTAssertFalse(app.buttons["Other Kindle"].exists, "Devices for other users are not listed")
        capture("item-send-devices")
        app.buttons["Shared Kindle"].tap()
        let result = app.staticTexts["send-ebook-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(result.label, "Ebook sent to Shared Kindle")
        let observed = try await ItemActionsFixture.observations()
        XCTAssertEqual(observed.sent, [["libraryItemId": "book-0", "deviceName": "Shared Kindle"]])
        let request = try XCTUnwrap(observed.requests.first { $0.path == "/api/emails/send-ebook-to-device" })
        XCTAssertEqual(request.body?.count, 2)
    }

    func testAFailedSendIsReportedAndSendingAgainSucceeds() async throws {
        let app = try await openBook("book-0", configure: ["role": "user", "fail": "send"])
        let send = app.buttons["send-ebook"]
        XCTAssertTrue(reveal(send, in: app), app.debugDescription)
        send.tap()
        XCTAssertTrue(app.buttons["Reading Tablet"].waitForExistence(timeout: 10))
        app.buttons["Reading Tablet"].tap()
        let error = app.staticTexts["item-action-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["send-ebook-result"].exists)
        send.tap()
        XCTAssertTrue(app.buttons["Reading Tablet"].waitForExistence(timeout: 10))
        app.buttons["Reading Tablet"].tap()
        XCTAssertTrue(app.staticTexts["send-ebook-result"].waitForExistence(timeout: 10))
        XCTAssertFalse(error.exists)
        let observed = try await ItemActionsFixture.observations()
        XCTAssertEqual(observed.sent, [["libraryItemId": "book-0", "deviceName": "Reading Tablet"]])
    }
}

enum ItemActionsFixture {
    struct Request { let method: String; let path: String; let body: [String: Any]? }
    struct Feed { let id: String }
    struct Observed { let requests: [Request]; let feeds: [Feed]; let sent: [[String: String]] }

    static func configure(_ options: [String: Any]) async throws {
        var request = URLRequest(url: URL(string: ItemServerActionsJourney.fixture + "/__actions__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: options)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    static func observations() async throws -> Observed {
        let (data, _) = try await URLSession.shared.data(from: URL(string: ItemServerActionsJourney.fixture + "/__actions__/observations")!)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let requests = (value["requests"] as? [[String: Any]] ?? []).map { Request(method: $0["method"] as? String ?? "", path: $0["path"] as? String ?? "", body: $0["body"] as? [String: Any]) }
        let feeds = (value["feeds"] as? [[String: Any]] ?? []).compactMap { ($0["id"] as? String).map(Feed.init) }
        return Observed(requests: requests, feeds: feeds, sent: value["sent"] as? [[String: String]] ?? [])
    }

    /// Waits until the app has read the account and the item's feed, so a missing action is not just still loading.
    static func waitForLoad(of itemID: String) async throws {
        for _ in 0..<50 {
            let requests = try await observations().requests
            if requests.contains(where: { $0.path == "/api/items/" + itemID }) && requests.contains(where: { $0.path == "/api/authorize" }) { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("The app did not load the actions for \(itemID)")
    }
}
