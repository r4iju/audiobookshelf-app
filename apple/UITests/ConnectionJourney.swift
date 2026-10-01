import XCTest

@MainActor final class ConnectionJourney: NativeJourney {
    func testConnectSelectLibraryAndRestoreAccountAfterRelaunch() {
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
    }

    func testQualifiedLANHTTPConnectsWithoutWeakeningHTTPSTrust() {
        connectSelectAndRestore(serverURL: "http://dev.nginx.lan:19765/abs")
        let app = XCUIApplication()
        app.buttons["account"].tap()
        app.buttons["account-signout"].tap()
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

    func testBrowsePaginatedBooksAndExpandedMetadata() {
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        let firstBook = app.buttons["book-book-0"]
        XCTAssertTrue(firstBook.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Continue listening"].exists)
        capture("native-catalog")
        firstBook.tap()
        XCTAssertTrue(app.staticTexts["Narrated by QA Narrator"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Opening"].exists)
        XCTAssertTrue(app.staticTexts["Next chapter"].exists)
        capture("native-book-details")
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

}
