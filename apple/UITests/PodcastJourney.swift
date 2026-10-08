import XCTest

@MainActor final class PodcastJourney: NativeJourney {
    func testDelayedPriorFailureCannotFailRetriedServerDownload() async throws {
        let app = try await queueFailingEpisode(mode: "podcast-retry-delayed-failure")
        try await finishDownloads()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 8))
        app.buttons["Retry failed episodes"].tap()
        XCTAssertTrue(app.buttons["The Next Story"].waitForExistence(timeout: 5))
        app.buttons["The Next Story"].tap(); app.buttons["Add selected episodes to server"].tap()
        XCTAssertTrue(app.staticTexts["server-download-pending"].waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertFalse(app.staticTexts["Failed"].exists, "A delayed receipt for the old job must not fail the new request")
        XCTAssertTrue(app.staticTexts["server-download-pending"].exists)
        try await finishDownloads()
        XCTAssertTrue(app.buttons["episode-episode-new"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Failed"].exists)
        XCTAssertFalse(app.staticTexts["server-download-pending"].exists)
    }
    private func finishDownloads() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs/__fixture__/finish-downloads")!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    func testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast() async throws {
        let app = try await queueFailingEpisode(mode: "podcast-held-download-failure")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["book-podcast"].waitForExistence(timeout: 5))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs/__fixture__/finish-downloads")!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        app.buttons["book-podcast"].tap()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 5), "A completed server event must be saved while its podcast screen is closed")
        XCTAssertFalse(app.staticTexts["server-download-pending"].exists)
    }
    private func queueFailingEpisode(mode: String = "podcast-download-failure") async throws -> XCUIApplication {
        try await FixtureControl.configure(mode)
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); accountMenu(app).buttons["Change library"].tap(); app.buttons["library-podcasts"].tap()
        app.buttons["book-podcast"].tap(); app.buttons["Feed episodes"].tap()
        XCTAssertTrue(app.buttons["The Next Story"].waitForExistence(timeout: 5))
        app.buttons["The Next Story"].tap(); app.buttons["Add selected episodes to server"].tap()
        return app
    }
    func testFailedActiveServerDownloadStopsWaitingAndRetainsRecoveryAfterRelaunch() async throws {
        let app = try await queueFailingEpisode()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 12), "A failed active job is absent from the queue and must be recovered through its server event. " + app.debugDescription)
        guard app.staticTexts["Failed"].exists else { return }
        XCTAssertFalse(app.staticTexts["server-download-pending"].exists)
        XCTAssertTrue(app.buttons["Retry failed episodes"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["book-podcast"].tap()
        XCTAssertTrue(app.staticTexts["Failed"].waitForExistence(timeout: 5), "Keep the recovery state when the server no longer has the completed job")
        XCTAssertFalse(app.staticTexts["server-download-pending"].exists)
    }
    func testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed() async throws {
        try await FixtureControl.configure("podcast-admin")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["account"].tap()
        app.buttons["Add podcast"].tap()
        let query = app.textFields["podcast-discovery-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        guard query.exists else { return }
        query.tap()
        query.typeText("New Voices\n")
        app.buttons["Search podcasts"].tap()
        XCTAssertTrue(app.buttons["podcast-discovery-42"].waitForExistence(timeout: 5))
        app.buttons["podcast-discovery-42"].tap()
        XCTAssertTrue(app.textFields["podcast-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["podcast-title"].value as? String, "New Voices Discovery")
        app.buttons["Create podcast"].tap()
        XCTAssertTrue(app.buttons["book-podcast-new"].waitForExistence(timeout: 10))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/search/podcast" })
    }

    func testStaleDetailRefreshCannotUndoNewEpisodeCompletion() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["book-podcast"].tap()
        XCTAssertTrue(app.buttons["episode-episode-morning"].waitForExistence(timeout: 5))
        try await FixtureControl.configure("podcast-slow-detail")
        app.buttons["episode-episode-morning"].tap()
        app.buttons["Mark finished"].tap()
        XCTAssertTrue(app.buttons["Mark unfinished"].waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 6_000_000_000)
        XCTAssertTrue(app.buttons["Mark unfinished"].exists)
        XCTAssertFalse(app.buttons["Mark finished"].exists)
    }
    func testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer() async throws {
        try await FixtureControl.configure("podcast-admin")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["book-podcast"].tap()
        let feed = app.buttons["Feed episodes"]
        XCTAssertTrue(feed.waitForExistence(timeout: 3))
        guard feed.exists else { return }
        feed.tap()
        let episode = app.buttons["The Next Story"]
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.tap()
        app.buttons["Add selected episodes to server"].tap()
        XCTAssertFalse(app.buttons["episode-episode-new"].exists)
        XCTAssertTrue(app.buttons["episode-episode-new"].waitForExistence(timeout: 10))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/podcasts/podcast/download-episodes" })
    }

    func testEpisodeCompletionPersistsAndFiltersThePodcastList() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["book-podcast"].tap()
        app.buttons["episode-episode-morning"].tap()
        let finish = app.buttons["Mark finished"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        guard finish.exists else { return }
        finish.tap()
        XCTAssertTrue(app.buttons["Mark unfinished"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-podcast"].tap()
        app.buttons["Filter episodes"].tap()
        app.buttons["Complete"].tap()
        XCTAssertTrue(app.buttons["episode-episode-morning"].exists)
        XCTAssertFalse(app.buttons["episode-episode"].exists)
        app.buttons["episode-episode-morning"].tap()
        app.buttons["Mark unfinished"].tap()
        XCTAssertTrue(app.buttons["Mark finished"].waitForExistence(timeout: 5))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/me/progress/podcast/episode-morning" })
    }

    func testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["account"].tap()
        XCTAssertFalse(app.buttons["Add podcast"].exists)
        app.buttons["Refresh"].tap()
        try await FixtureControl.configure("podcast-admin")
        app.buttons["account"].tap()
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.buttons["book-podcast"].waitForExistence(timeout: 5))
        app.buttons["account"].tap()
        let add = app.buttons["Add podcast"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        guard add.exists else { return }
        add.tap()
        app.textFields["podcast-feed-url"].tap()
        app.textFields["podcast-feed-url"].typeText("http://127.0.0.1:19765/feed.xml\n")
        app.buttons["Preview feed"].tap()
        XCTAssertTrue(app.textFields["podcast-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["podcast-title"].value as? String, "New Voices")
        app.buttons["Create podcast"].tap()
        XCTAssertTrue(app.buttons["book-podcast-new"].waitForExistence(timeout: 10))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/podcasts/feed" })
        XCTAssertTrue(requests.contains { $0.path == "/api/podcasts" })
    }

    func testPodcastEpisodeSelectionKeepsIndependentProgressThroughRelaunch() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        app.buttons["book-podcast"].tap()
        let morning = app.buttons["episode-episode-morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 5))
        guard morning.exists else { return }
        morning.tap()
        XCTAssertTrue(app.staticTexts["20 sec"].waitForExistence(timeout: 3))
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        app.buttons["pause-playback"].tap()
        let saved = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertGreaterThan(saved, 6)
        app.buttons["Close playback"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-podcast"].tap()
        app.buttons["episode-episode-morning"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["pause-playback"].tap()
        let restored = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertGreaterThanOrEqual(restored, saved)
        app.buttons["Close playback"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["episode-episode"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["pause-playback"].tap()
        let untouched = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertLessThan(untouched, saved)
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/items/podcast/play/episode-morning" })
        XCTAssertTrue(requests.contains { $0.path == "/api/items/podcast/play/episode" })
    }
}
