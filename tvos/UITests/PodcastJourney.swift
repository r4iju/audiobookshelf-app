import XCTest

/// Story #29: episode browsing, playback and completion stay separate from audiobooks.
final class PodcastJourney: TVJourney {
    func openPodcast() {
        signIn()
        waitForHome()
        library("Podcasts")
        select(app.buttons["item-podcast"])
        XCTAssertTrue(app.buttons["episode-episode-morning"].waitForExistence(timeout: 10))
    }

    func testEpisodesSortAndPlaySeparatelyFromBooks() async throws {
        openPodcast()
        let morning = app.buttons["episode-episode-morning"], evening = app.buttons["episode-episode"]
        XCTAssertLessThan(morning.frame.minY, evening.frame.minY, "Newest episode first")
        select(app.buttons["episode-sort"])
        XCTAssertEqual(app.buttons["episode-sort"].label, "Oldest first")
        XCTAssertLessThan(evening.frame.minY, morning.frame.minY)
        capture("episodes")
        select(evening)
        XCTAssertEqual(label("episode-title"), "A Quiet Evening")
        select(app.buttons["play-episode"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        XCTAssertEqual(label("now-playing-title"), "A Quiet Evening")
        sleep(3)
        select(app.buttons["stop-playback"])
        var sessions: [Fixture.LocalSession] = []
        for _ in 0..<20 where sessions.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            sessions = try await observations().localSessions.filter { $0.episodeId == "episode" }
        }
        XCTAssertEqual(sessions.first?.libraryItemId, "podcast")
        XCTAssertGreaterThan(sessions.first?.timeListening ?? 0, 1)
        let books = try await observations().localSessions.filter { $0.libraryItemId == "book-0" }
        XCTAssertTrue(books.isEmpty)
    }

    func testMarkEpisodeFinishedUpdatesOnlyThatEpisode() async throws {
        openPodcast()
        select(app.buttons["episode-episode-morning"])
        let toggle = app.buttons["mark-finished"]
        XCTAssertEqual(toggle.waitForExistence(timeout: 10) ? toggle.label : "", "Mark as finished")
        select(toggle)
        wait(toggle, label: "Mark as not finished")
        let requests = try await observations().requests
        XCTAssertTrue(requests.contains { $0.method == "PATCH" && $0.path == "/api/me/progress/podcast/episode-morning" })
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["episode-state-episode-morning"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("episode-state-episode-morning"), "Finished")
        XCTAssertFalse(app.staticTexts["episode-state-episode"].exists)
    }

    func testPodcastResultTileShowsItsEpisodeProgress() async throws {
        openPodcast()
        select(app.buttons["episode-episode"])
        select(app.buttons["mark-finished"])
        wait(app.buttons["mark-finished"], label: "Mark as not finished")
        tab("Search")
        search("Quiet")
        let tile = app.buttons["search.podcast.episode"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertEqual(tile.value as? String, "Finished", "The tile reflects the matched episode, not the podcast as a book")
    }
}
