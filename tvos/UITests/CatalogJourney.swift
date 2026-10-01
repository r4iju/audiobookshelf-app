import XCTest

/// Story #26: remote-operated connection, home, library, search, filters and details.
final class CatalogJourney: TVJourney {
    func testContinueListeningOpensDetailsAndBackRestoresFocus() {
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "Stories for Tomorrow 01")
        XCTAssertEqual(label("detail-narrators"), "Narrated by QA Narrator")
        XCTAssertEqual(label("detail-progress"), "0:06 of 0:20 listened")
        XCTAssertEqual(app.buttons["play-item"].label, "Resume")
        capture("detail")
        remote.press(.menu)
        let tile = app.buttons["continue-listening.book-0"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(tile), "Back should return focus to the tile that opened the details")
    }

    func testLibraryLoadsNextPageAsFocusMovesDown() async throws {
        signIn()
        waitForHome()
        tab("Audiobooks")
        XCTAssertTrue(app.buttons["item-book-0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["loadMore"].exists)
        let last = app.buttons["item-book-60"]
        for _ in 0..<30 where !last.exists { remote.press(.down) }
        XCTAssertTrue(last.waitForExistence(timeout: 10), "The 61st title should load without a separate button")
        let pages = try await observations().requests.filter { $0.path == "/api/libraries/books/items" }.compactMap(\.page)
        XCTAssertEqual(Set(pages), ["0", "1"])
        capture("library-end")
    }

    func testServerSearchFindsTitlesOutsideLoadedPage() async throws {
        signIn()
        waitForHome()
        tab("Search")
        search("Tomorrow 61")
        let result = app.buttons["search.book-60"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        let searched = try await observations().requests.contains { $0.path == "/api/libraries/books/search" }
        XCTAssertTrue(searched)
        capture("search")
        select(result)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "Stories for Tomorrow 61")
    }

    func testFilterAndSortAreAppliedByTheServer() {
        signIn()
        waitForHome()
        tab("Audiobooks")
        XCTAssertTrue(app.buttons["item-book-0"].waitForExistence(timeout: 10))
        select(app.buttons["library-filter"])
        select(menuItem("Mystery"))
        XCTAssertTrue(app.buttons["item-book-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["item-book-0"].exists)
        XCTAssertEqual(app.buttons["library-filter"].label, "Filter: Mystery")
        select(app.buttons["library-sort"])
        select(menuItem("Title Z–A"))
        let first = app.buttons["item-book-59"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.minY, app.buttons["item-book-1"].exists ? app.buttons["item-book-1"].frame.minY : .greatestFiniteMagnitude)
        capture("filtered")
    }

    func testProgressFilterDropsATitleMarkedFinishedOnReturn() {
        signIn()
        waitForHome()
        tab("Audiobooks")
        XCTAssertTrue(app.buttons["item-book-0"].waitForExistence(timeout: 10))
        select(app.buttons["library-filter"])
        select(menuItem("Not started"))
        let title = app.buttons["item-book-1"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["item-book-0"].exists, "In-progress titles are excluded")
        select(title)
        select(app.buttons["mark-finished"])
        wait(app.buttons["mark-finished"], label: "Mark as not finished")
        remote.press(.menu)
        XCTAssertTrue(app.buttons["item-book-2"].waitForExistence(timeout: 10))
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: title)], timeout: 10), .completed, "A finished title leaves the Not started results")
        XCTAssertEqual(app.buttons["library-filter"].label, "Filter: Not started")
    }

    func testCatalogFailureRecoversWithRetry() async throws {
        try await Fixture.configure("offline-library")
        signIn()
        let retry = app.buttons["retry-catalog"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["catalog-error"].exists)
        capture("catalog-error")
        try await Fixture.configure("baseline")
        select(retry)
        waitForHome()
    }

    func testTrustedHTTPSServerAndLongMetadata() async throws {
        let secure = "https://127.0.0.1:20767/abs"
        try await Fixture.configure("edge-metadata", base: secure)
        addTeardownBlock { try await Fixture.configure("baseline", base: secure) }
        signIn(server: secure)
        waitForHome()
        let tile = app.buttons["continue-listening.book-0"]
        XCTAssertTrue(tile.label.hasPrefix("A Very Long Story Title"))
        XCTAssertTrue(app.images["cover-placeholder"].firstMatch.exists, "A missing cover should show the placeholder")
        select(tile)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(label("detail-title").hasSuffix("Forgotten Libraries"))
        capture("long-title")
        tab("Settings")
        XCTAssertEqual(label("server-address"), secure)
        XCTAssertTrue(label("auth-modes").contains("username and password"))
    }
}
