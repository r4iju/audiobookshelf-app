import XCTest

/// Story #27: one authoritative session controlled from the remote and on-screen controls.
final class PlaybackJourney: TVJourney {
    func startContinueListening() {
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
    }

    /// The fixture resumes two seconds before chapter 2, so pause before navigating to a chapter.
    func chooseNextChapterWhilePaused() {
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        select(app.buttons["chapters"])
        select(app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Next chapter")).firstMatch)
        wait(app.staticTexts["now-playing-chapter"], label: "Next chapter · Chapter 2 of 2")
        XCTAssertEqual(label("now-playing-elapsed"), "0:08")
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
    }

    func testResumeShowsChapterAndTotalProgressAndRemoteToggles() {
        startContinueListening()
        XCTAssertEqual(label("now-playing-title"), "Stories for Tomorrow 01")
        XCTAssertEqual(label("now-playing-chapter"), "Opening · Chapter 1 of 2")
        XCTAssertGreaterThanOrEqual(seconds("now-playing-elapsed"), 6)
        capture("now-playing")
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let paused = seconds("now-playing-elapsed")
        sleep(2)
        XCTAssertEqual(seconds("now-playing-elapsed"), paused)
        focus(app.tabBars.buttons["Now Playing"])
        capture("now-playing-unfocused")
        focus(app.buttons["toggle-playback"])
        capture("now-playing-focused")
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
    }

    func testNextChapterCrossesFilesAndLeavingThePlayerKeepsPlaying() {
        startContinueListening()
        chooseNextChapterWhilePaused()
        let left = seconds("now-playing-elapsed")
        tab("Listen Now")
        XCTAssertTrue(app.buttons["play-item"].waitForExistence(timeout: 5), "Listen Now keeps the details that started playback")
        tab("Now Playing")
        // The fixture has 12 seconds left, so the book may have finished while away; it must not pause.
        XCTAssertNotEqual(label("playback-status"), "Paused")
        XCTAssertGreaterThan(seconds("now-playing-elapsed"), left + 1)
    }

    func testSpeedSelectionAndExplicitStopClosesTheSession() async throws {
        startContinueListening()
        select(app.buttons["playback-speed"])
        select(menuItem("1.5×"))
        wait(app.buttons["playback-speed"], label: "Speed 1.5×")
        select(app.buttons["stop-playback"])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.tabBars.buttons["Now Playing"])
        await fulfillment(of: [gone], timeout: 15)
        let requests = try await observations().requests
        XCTAssertTrue(requests.contains { $0.path.hasPrefix("/api/session/") && $0.path.hasSuffix("/close") })
    }

    func testNaturalEndShowsFinished() {
        startContinueListening()
        chooseNextChapterWhilePaused()
        wait(app.staticTexts["playback-status"], label: "Finished", timeout: 30)
        XCTAssertEqual(label("now-playing-elapsed"), "0:20")
    }

    /// Issue #112: starting another title while one plays replaces it in Now Playing and in the session.
    func testStartingAnotherTitleWhileOnePlaysReplacesIt() async throws {
        let earlier = try await observations().requests.count
        startContinueListening()
        library("Audiobooks")
        select(app.buttons["item-book-1"])
        wait(app.buttons["play-item"], label: "Play")
        select(app.buttons["play-item"])
        wait(app.staticTexts["now-playing-title"], label: "Stories for Tomorrow 02", timeout: 20)
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        sleep(3)
        XCTAssertEqual(label("now-playing-title"), "Stories for Tomorrow 02", "The earlier title must not come back")
        let requests = try await observations().requests.dropFirst(earlier).filter { $0.method == "POST" }.map(\.path)
        let firstPlay = requests.firstIndex(of: "/api/items/book-0/play"), secondPlay = requests.firstIndex(of: "/api/items/book-1/play")
        XCTAssertNotNil(firstPlay, "\(requests)")
        XCTAssertNotNil(secondPlay, "The second title must open its own session: \(requests)")
        if let firstPlay, let secondPlay {
            XCTAssertTrue(requests[firstPlay..<secondPlay].contains { $0.hasPrefix("/api/session/") && $0.hasSuffix("/close") },
                          "The first session closes before the second opens: \(requests)")
        }
        XCTAssertEqual(requests.filter { $0 == "/api/items/book-0/play" }.count, 1, "The first title must not be started again: \(requests)")
    }

    /// Issue #112: a start that cannot replace the playing title says so on the chosen title instead of showing the
    /// earlier one in Now Playing. The server refuses the earlier session's save and close here.
    func testAStartThatCannotReplaceThePlayingTitleStaysOnTheChosenTitle() async throws {
        startContinueListening()
        try await Fixture.configure("offline-progress")
        library("Audiobooks")
        select(app.buttons["item-book-1"])
        wait(app.buttons["play-item"], label: "Play")
        select(app.buttons["play-item"])
        XCTAssertTrue(app.staticTexts["detail-error"].waitForExistence(timeout: 20), "The chosen title explains why it did not start")
        sleep(2)
        XCTAssertTrue(app.buttons["play-item"].exists, "The chosen title stays open")
        XCTAssertFalse(app.staticTexts["now-playing-title"].exists, "Now Playing must not open on the earlier title")
    }
}
