import XCTest

@MainActor final class SearchJourney: NativeJourney {
    func testSearchInputBelongsToSearchAndCancelAllowsOtherDestinations() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        mainDestination("Settings", in: app).tap()
        XCTAssertTrue(app.buttons["language-settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists, "Settings must not own Library search input")
        mainDestination("Search", in: app).tap()
        let query = librarySearchField(app)
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.typeText("Tomorrow 61\n")
        XCTAssertTrue(app.buttons["search-book-60"].waitForExistence(timeout: 10))
        let cancelled = app.buttons["Close"].exists
        if cancelled { app.buttons["Close"].tap() }
        mainDestination("Settings", in: app).tap()
        XCTAssertTrue(app.buttons["language-settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists, "Leaving Search removes its input from Settings")
        mainDestination("Search", in: app).tap()
        let reopened = librarySearchField(app)
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        let emptyValue = reopened.value as? String
        if cancelled {
            XCTAssertTrue(emptyValue == "" || emptyValue == "Books, podcasts, authors, series…", "Native Cancel clears the query")
            reopened.typeText("Tomorrow 61\n")
        } else {
            XCTAssertEqual(emptyValue, "Tomorrow 61", "Leaving Search without Cancel retains its query")
            reopened.typeText("\n")
        }
        XCTAssertTrue(app.buttons["search-book-60"].waitForExistence(timeout: 10), "Re-entering Search uses the selected library")
    }

    func testSelectingSearchAcceptsTypingWithoutAnotherActivation() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        mainDestination("Search", in: app).tap()
        let query = librarySearchField(app)
        XCTAssertTrue(query.waitForExistence(timeout: 5), "Selecting Search exposes its native input")
        guard query.exists else { return }
        query.typeText("Tomorrow 61\n")
        XCTAssertTrue(app.buttons["search-book-60"].waitForExistence(timeout: 10), "The selected Search input accepts typing and keyboard submission")
    }

    func testEpisodeOnlySearchNavigatesAndPlaysTheMatchingPodcastEpisode() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(mainDestination("Search", in: app).waitForExistence(timeout: 5))
        mainDestination("Search", in: app).tap()
        librarySearchField(app).tap()
        librarySearchField(app).typeText("Quiet Evening\n")
        let episode = app.buttons["search-episode-episode"]
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        guard episode.exists else { return }
        episode.tap()
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        app.buttons["mini-pause-playback"].tap()
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/items/podcast/play/episode" })
        XCTAssertTrue(requests.contains { $0.path == "/audio/0" })
    }
    func testSortingAndGenreFilteringUseTheServerAcrossPagination() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        let sort = app.buttons["Sort library"]
        XCTAssertTrue(sort.waitForExistence(timeout: 3))
        guard sort.exists else { return }
        sort.tap()
        app.buttons["Title Z–A"].tap()
        XCTAssertTrue(app.buttons["book-book-60"].waitForExistence(timeout: 10))
        app.buttons["Filter library"].tap()
        app.buttons["Genres"].tap()
        app.buttons["Mystery"].tap()
        XCTAssertTrue(app.buttons["book-book-59"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["book-book-60"].exists)
        XCTAssertFalse(app.buttons["book-book-0"].exists)
    }
    func testSearchFindsBookBeyondFirstPageAndReturnsFromDetails() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        let search = mainDestination("Search", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        guard search.exists else { return }
        search.tap()
        let query = librarySearchField(app)
        query.tap()
        query.typeText("Tomorrow 61\n")
        XCTAssertTrue(app.buttons["search-book-60"].waitForExistence(timeout: 10))
        app.buttons["search-book-60"].tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Search"].tap()
        XCTAssertTrue(app.buttons["search-book-60"].exists)
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/libraries/books/search" })
    }
}
