import XCTest

/// Story #28: unsent listening survives termination and is reported exactly once.
final class RecoveryJourney: TVJourney {
    func testUnsentListeningSurvivesTerminationAndSyncsOnRelaunch() async throws {
        try await Fixture.configure("offline-progress")
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        sleep(4)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        XCTAssertTrue(app.staticTexts["playback-error"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["retry-sync"].exists, "A progress failure offers to save again")
        XCTAssertFalse(app.buttons["restart-playback"].exists)
        let listenedTo = seconds("now-playing-elapsed")
        XCTAssertGreaterThan(listenedTo, 6)
        app.terminate()
        try await Fixture.configure("baseline")
        let cleared = try await observations().localSessions
        XCTAssertTrue(cleared.isEmpty)

        launch(reset: false)
        waitForHome()
        var sessions: [Fixture.LocalSession] = []
        for _ in 0..<30 where sessions.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            sessions = try await observations().localSessions
        }
        let recovered = try XCTUnwrap(sessions.first { $0.libraryItemId == "book-0" }, "Relaunch should send the saved listening")
        XCTAssertGreaterThanOrEqual(Int(recovered.currentTime), listenedTo - 1)
        XCTAssertGreaterThan(recovered.timeListening, 2)
        select(app.buttons["continue-listening.book-0"])
        XCTAssertTrue(app.staticTexts["detail-progress"].waitForExistence(timeout: 10))
        XCTAssertNotEqual(label("detail-progress"), "0:06 of 0:20 listened")

        let reported = try await observations().reports.count
        app.terminate()
        launch(reset: false)
        waitForHome()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let after = try await observations()
        XCTAssertEqual(after.reports.count, reported, "A delivered report must not be sent again")
        XCTAssertEqual(after.localSessions.filter { $0.libraryItemId == "book-0" }.map(\.timeListening).reduce(0, +), recovered.timeListening, accuracy: 0.01)
    }

    func testMediaFailureOffersRestartRatherThanSavingProgress() async throws {
        try await Fixture.configure("broken-audio")
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        let restart = app.buttons["restart-playback"]
        XCTAssertTrue(restart.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["playback-error"].exists)
        XCTAssertFalse(app.buttons["retry-sync"].exists, "Saving progress again cannot fix unplayable audio")
        try await Fixture.configure("baseline")
        select(restart)
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 30)
        XCTAssertEqual(label("now-playing-title"), "Stories for Tomorrow 01")
        XCTAssertFalse(app.staticTexts["playback-error"].exists)
    }
}
