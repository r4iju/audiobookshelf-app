import XCTest

/// Runs against apple/scripts/verify-realtime.sh, which owns ports 26765 (Socket.IO and HTTP proxy) and 26769.
@MainActor final class RealtimeJourney: NativeJourney {
    private static let server = "http://127.0.0.1:26765/abs"
    private let otherUserID = "00000000-0000-4000-8000-000000000002"
    private let ownerUserID = "00000000-0000-4000-8000-000000000001"

    func testProgressFromAnotherClientUpdatesTheOpenShelfAndBookDetails() async throws {
        let app = try await openBooks()
        XCTAssertTrue(app.buttons["continue-book-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["continue-book-3"].exists)
        try await remote(["change": "progress", "itemId": "book-3", "currentTime": 10])
        XCTAssertTrue(app.buttons["continue-book-3"].waitForExistence(timeout: 8), "Progress saved by another client must reach Continue Listening without a manual refresh")
        try await remote(["change": "progress", "itemId": "book-0", "currentTime": 15])
        XCTAssertTrue(text(app, containing: "75% listened").waitForExistence(timeout: 8), "An existing Continue Listening card must show the other client's position")
        app.buttons["continue-book-3"].tap()
        XCTAssertTrue(text(app, containing: "50% complete").waitForExistence(timeout: 5))
        try await remote(["change": "progress", "itemId": "book-3", "currentTime": 16])
        XCTAssertTrue(text(app, containing: "80% complete").waitForExistence(timeout: 8), "Open book details must follow progress from another client")
        capture("realtime-book-details-progress")
    }

    func testItemAndPlaylistChangesFromAnotherClientAppearWhileVisible() async throws {
        let app = try await openBooks()
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 02"].waitForExistence(timeout: 5))
        try await remote(["change": "item-title", "itemId": "book-1", "title": "Renamed Elsewhere"])
        XCTAssertTrue(app.staticTexts["Renamed Elsewhere"].waitForExistence(timeout: 8), "A library item edited elsewhere must update the open shelf")
        app.buttons["account"].tap(); app.buttons["Playlists"].tap()
        XCTAssertTrue(app.buttons["group-playlist-evening"].waitForExistence(timeout: 5))
        try await remote(["change": "playlist-add", "name": "Shared from elsewhere"])
        XCTAssertTrue(app.buttons["group-playlist-remote"].waitForExistence(timeout: 8), "A playlist created by another client must appear in the open list")
        try await remote(["change": "playlist-rename", "playlistId": "playlist-evening", "name": "Renamed queue"])
        XCTAssertTrue(app.staticTexts["Renamed queue"].waitForExistence(timeout: 8))
        try await remote(["change": "playlist-remove", "playlistId": "playlist-remote"])
        XCTAssertTrue(disappears(app.buttons["group-playlist-remote"], timeout: 8), "A playlist removed elsewhere must leave the open list")
        app.buttons["group-playlist-evening"].tap()
        XCTAssertTrue(app.buttons["Play playlist"].waitForExistence(timeout: 5))
        try await remote(["change": "playlist-rename", "playlistId": "playlist-evening", "name": "Evening queue, again"])
        XCTAssertTrue(app.navigationBars["Evening queue, again"].waitForExistence(timeout: 8), "Open playlist details must follow a rename from another client")
        try await remote(["change": "playlist-remove", "playlistId": "playlist-evening"])
        XCTAssertTrue(disappears(app.buttons["Play playlist"], timeout: 8), "Open playlist details must close when another client deletes the playlist")
        XCTAssertFalse(app.buttons["group-playlist-evening"].exists)
    }

    func testReconnectionRefreshesChangesMissedWhileDisconnected() async throws {
        let app = try await openBooks()
        XCTAssertTrue(app.buttons["continue-book-0"].waitForExistence(timeout: 5))
        try await waitForRealtime(userID: ownerUserID)
        try await remote(["change": "silent-progress", "itemId": "book-5", "currentTime": 4])
        try await remote(["change": "disconnect"])
        XCTAssertTrue(app.buttons["continue-book-5"].waitForExistence(timeout: 15), "Re-authentication after a dropped socket must refresh state changed while no events could arrive")
    }

    func testSwitchingAccountsClosesTheOldStreamAndFollowsTheNewAccount() async throws {
        let app = try await openBooks()
        try await waitForRealtime(userID: ownerUserID)
        app.buttons["account"].tap(); app.buttons["Saved connections"].tap(); app.buttons["Add server"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap(); server.typeText(Self.server)
        app.textFields["username"].tap(); app.textFields["username"].typeText("qa-other")
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 10))
        app.buttons["library-books"].tap()
        XCTAssertTrue(app.buttons["continue-book-0"].waitForExistence(timeout: 10))
        try await waitForRealtime(userID: otherUserID)
        let open = try await realtimeConnections()
        XCTAssertNil(open[ownerUserID], "The previous account's realtime stream must be closed after switching")
        try await remote(["change": "progress", "username": "qa", "itemId": "book-7", "currentTime": 10])
        try await remote(["change": "progress", "username": "qa-other", "itemId": "book-8", "currentTime": 10])
        XCTAssertTrue(app.buttons["continue-book-8"].waitForExistence(timeout: 8), "The newly selected account must receive its own realtime progress")
        XCTAssertFalse(app.buttons["continue-book-7"].exists, "Progress for the previous account must not appear")
    }

    func testSigningInAgainToTheSameAccountKeepsRealtimeUpdates() async throws {
        let app = try await openBooks()
        try await waitForRealtime(userID: ownerUserID)
        app.buttons["account"].tap(); app.buttons["Saved connections"].tap(); app.buttons["Add server"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap(); server.typeText(Self.server)
        app.textFields["username"].tap(); app.textFields["username"].typeText("qa")
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        if app.buttons["library-books"].waitForExistence(timeout: 5) { app.buttons["library-books"].tap() }
        XCTAssertTrue(app.buttons["continue-book-0"].waitForExistence(timeout: 10))
        try await remote(["change": "progress", "itemId": "book-9", "currentTime": 10])
        XCTAssertTrue(app.buttons["continue-book-9"].waitForExistence(timeout: 8), "A new sign-in to the same account must keep receiving realtime changes")
    }

    private func openBooks() async throws -> XCUIApplication {
        try await post("configure", ["mode": "baseline"])
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false)
        return XCUIApplication()
    }
    private func text(_ app: XCUIApplication, containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
    private func disappears(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
    private func remote(_ change: [String: Any]) async throws { try await post("remote-change", change) }
    private func post(_ path: String, _ body: [String: Any]) async throws {
        var request = URLRequest(url: URL(string: Self.server + "/__fixture__/" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, path)
    }
    private func realtimeConnections() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: Self.server + "/__fixture__/realtime-connections")!)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
    private func waitForRealtime(userID: String) async throws {
        for _ in 0..<40 {
            if try await realtimeConnections()[userID] != nil { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTFail("The app did not open an authenticated realtime stream for \(userID)")
    }
}
