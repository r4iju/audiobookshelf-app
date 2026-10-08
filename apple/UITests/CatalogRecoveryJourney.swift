import XCTest

@MainActor final class CatalogRecoveryJourney: NativeJourney {
    func testLongMetadataAndMissingArtworkRemainNavigableForReadOnlyAccount() async throws {
        try await FixtureControl.configure("edge-metadata")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        let book = app.buttons["book-book-0"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        guard book.exists else { return }
        book.tap()
        XCTAssertTrue(app.staticTexts["Narrated by QA Narrator"].waitForExistence(timeout: 5))
        let chapter = app.staticTexts["Opening"]
        for _ in 0..<5 where !chapter.exists { app.swipeUp() }
        XCTAssertTrue(chapter.exists)
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["Show list"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].exists)
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/items/book-0/cover" })
    }

    func testEmptyLibraryCanBeRefreshedWithoutSigningInAgain() async throws {
        try await FixtureControl.configure("empty")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        XCTAssertTrue(app.staticTexts["This library is empty. Add titles on your server, then refresh."].waitForExistence(timeout: 5))
        try await FixtureControl.configure("baseline")
        app.buttons["Library actions"].tap()
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
    }

    func testCatalogFailureCanBeRetried() async throws {
        try await FixtureControl.configure("catalog-error")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        let app = XCUIApplication()
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        // Reconfigure after relaunch so the request under test owns this failure.
        try await FixtureControl.configure("catalog-error")
        app.buttons["Library actions"].tap()
        app.buttons["Refresh"].tap()
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
    }

    func testFailedNextPagePreservesBooksAndRetries() async throws {
        try await FixtureControl.configure("page-error")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        let retry = app.buttons["Try again"]
        for _ in 0..<20 {
            if retry.exists { break }
            app.scrollViews["catalog"].swipeUp()
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["book-book-59"].exists)
        retry.tap()
        XCTAssertTrue(app.buttons["book-book-60"].waitForExistence(timeout: 10))
    }
}
