import XCTest

@MainActor final class SearchJourney: NativeJourney {
    func testEpisodeOnlySearchNavigatesAndPlaysTheMatchingPodcastEpisode() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.buttons["Search library"].waitForExistence(timeout: 5))
        app.buttons["Search library"].tap()
        app.textFields["library-search"].tap()
        app.textFields["library-search"].typeText("Quiet Evening\n")
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
        let search = app.buttons["Search library"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        guard search.exists else { return }
        search.tap()
        let query = app.textFields["library-search"]
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
