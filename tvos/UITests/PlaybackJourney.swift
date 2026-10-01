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
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
    }

    func testNextChapterCrossesFilesAndLeavingThePlayerKeepsPlaying() {
        startContinueListening()
        chooseNextChapterWhilePaused()
        let left = seconds("now-playing-elapsed")
        tab("Home")
        XCTAssertTrue(app.buttons["play-item"].waitForExistence(timeout: 5), "Home keeps the details that started playback")
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
}
