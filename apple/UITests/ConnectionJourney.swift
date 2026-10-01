import XCTest

final class ConnectionJourney: XCTestCase {
    func testConnectSelectLibraryAndRestoreAccountAfterRelaunch() {
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
    }

    func testQualifiedLANHTTPConnectsWithoutWeakeningHTTPSTrust() {
        connectSelectAndRestore(serverURL: "http://dev.nginx.lan:19765/abs")
        let app = XCUIApplication()
        app.buttons["account"].tap()
        app.buttons["Sign out"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        if let current = server.value as? String {
            server.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        server.typeText("https://dev.nginx.lan:19767/abs")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        let error = app.staticTexts["connection-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("certificate") || error.label.contains("TLS"))
        XCTAssertFalse(app.buttons["library-books"].exists)
    }

    private func connectSelectAndRestore(serverURL: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText(serverURL)
        let username = app.textFields["username"]
        username.tap()
        username.typeText("qa")
        let password = app.secureTextFields["password"]
        password.tap()
        password.typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 10), app.staticTexts["connection-error"].exists ? app.staticTexts["connection-error"].label : app.debugDescription)
        app.buttons["library-books"].tap()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields["password"].exists)
    }

    func testBrowsePaginatedBooksAndExpandedMetadata() {
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        let firstBook = app.buttons["book-book-0"]
        XCTAssertTrue(firstBook.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Continue listening"].exists)
        firstBook.tap()
        XCTAssertTrue(app.staticTexts["Narrated by QA Narrator"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Opening"].exists)
        XCTAssertTrue(app.staticTexts["Next chapter"].exists)
        app.navigationBars.buttons["Audiobooks"].tap()
        let lastBook = app.buttons["book-book-60"]
        for _ in 0..<20 {
            if lastBook.exists { break }
            app.scrollViews["catalog"].swipeUp()
        }
        XCTAssertTrue(lastBook.waitForExistence(timeout: 5))
        lastBook.tap()
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 61"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testContinueListeningIncludesBookOutsideFirstCatalogPage() async throws {
        let cursor = try await fixtureRequests().count
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        let continuing = app.buttons["continue-book-60"]
        XCTAssertTrue(continuing.waitForExistence(timeout: 10))
        let requests = try await fixtureRequests()
        XCTAssertFalse(requests.dropFirst(cursor).contains { $0.path == "/api/libraries/books/items" && $0.page == "1" }, "Continue Listening must not depend on eagerly fetching subsequent catalog pages")
        continuing.tap()
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 61"].firstMatch.waitForExistence(timeout: 10))
    }

    func testInvalidServerShowsRecoveryWithoutLeavingConnectionForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("file:///tmp/books")
        app.textFields["username"].tap()
        app.textFields["username"].typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["server"].exists)
        XCTAssertEqual(app.textFields["server"].value as? String, "file:///tmp/books")
    }
    private struct ObservedRequest: Decodable {
        let path: String
        let page: String?
    }
    private struct Observations: Decodable { let requests: [ObservedRequest] }
    private func fixtureRequests() async throws -> [ObservedRequest] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:19765/abs/__fixture__/observations")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(Observations.self, from: data).requests
    }

}
