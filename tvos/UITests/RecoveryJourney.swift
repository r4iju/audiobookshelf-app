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

    /// Story 14 on the TV: a login the server revoked is signed in again on a form the remote can read and reach
    /// whole, for the same account and server; Back leaves the book paused, and the listening held meanwhile is
    /// sent once the account signs in again, without playing by itself.
    func testSigningInAgainShowsTheWholeFormAndSendsTheHeldListeningWithoutPlaying() async throws {
        launch(reset: true)
        assertSignInFormFits("First sign-in")
        enter(TVJourney.fixture, into: app.textFields["serverURL"])
        enter("qa", into: app.textFields["username"])
        enter("qa", into: app.secureTextFields["password"])
        select(app.buttons["connect"])
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        sleep(2)
        try await Fixture.revoke("qa")
        let revoked = try await observations().reports.count
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let alert = app.alerts["Sign in again"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Pausing for a revoked login did not ask to sign in again")
        let stoppedAt = seconds("now-playing-elapsed")
        select(alert.buttons["Sign in"].firstMatch)

        let password = app.secureTextFields["password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        capture("Signing in again")
        assertSignInFormFits("Signing in again")
        XCTAssertEqual(app.textFields["serverURL"].value as? String, TVJourney.fixture)
        XCTAssertEqual(app.textFields["username"].value as? String, "qa")
        XCTAssertFalse(app.textFields["serverURL"].isEnabled)
        XCTAssertFalse(app.textFields["username"].isEnabled)
        focus(password)
        focus(app.buttons["connect"])
        focus(app.buttons["sign-in-diagnostics"])

        // Back closes sign-in and keeps the book paused where it stopped, its listening still held on the TV.
        remote.press(.menu)
        XCTAssertTrue(password.waitForNonExistence(timeout: 5), "Back did not close signing in again")
        wait(app.staticTexts["playback-status"], label: "Paused")
        sleep(2)
        XCTAssertEqual(seconds("now-playing-elapsed"), stoppedAt)
        let held = try await observations().reports.count
        XCTAssertEqual(held, revoked, "A revoked login's listening reached the server")

        select(app.buttons.matching(NSPredicate(format: "label == %@", "Sign in again")).firstMatch)
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        select(alert.buttons["Sign in"].firstMatch)
        enter("qa", into: password)
        let beforeSignIn = try await observations().requests.count
        select(app.buttons["connect"])
        XCTAssertTrue(password.waitForNonExistence(timeout: 15), "Signing in again did not close sign-in")

        var delivered: Fixture.Report?
        for _ in 0..<40 where delivered == nil {
            delivered = try await observations().reports.dropFirst(held).last { $0.path == "/api/session/local-all" && $0.userId == "00000000-0000-4000-8000-000000000001" }
            if delivered == nil { try await Task.sleep(nanoseconds: 250_000_000) }
        }
        let report = try XCTUnwrap(delivered, "The held listening was not sent after signing in again")
        XCTAssertEqual(report.currentTime, Double(stoppedAt), accuracy: 1)
        sleep(3)
        XCTAssertEqual(label("playback-status"), "Paused", "Audio started by itself after signing in again")
        XCTAssertEqual(seconds("now-playing-elapsed"), stoppedAt)
        let afterSignIn = try await observations().requests.dropFirst(beforeSignIn)
        XCTAssertFalse(afterSignIn.contains { $0.path.hasPrefix("/audio/") }, "Audio loaded again after signing in")
        capture("Signed in again")
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

    /// Server 2.30 has no request barrier: a save a gateway gave up on may still be applied, and
    /// would replace anything sent after it. Later listening waits on the TV until the owner
    /// confirms a server restart that was asked for after that save.
    func testLaterListeningWaitsForARequestedAndConfirmedServerRestart() async throws {
        try await Fixture.configure("held-sync")
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        sleep(3)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        var held = 0
        for _ in 0..<30 where held == 0 {
            try await Task.sleep(nanoseconds: 500_000_000)
            held = try await observations().heldHandlers
        }
        let seen = try await observations()
        XCTAssertEqual(held, 1, "Precondition: the first save was held by the fixture; requests: \(seen.requests.filter { !$0.path.hasPrefix("/__fixture__") }.map { ($0.method ?? "") + " " + $0.path }.suffix(25)), sessions: \(seen.localSessions.map(\.id))")

        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
        sleep(3)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let listenedTo = seconds("now-playing-elapsed")
        XCTAssertTrue(app.staticTexts["now-playing-saves-waiting"].waitForExistence(timeout: 10), "Now Playing should say that newer listening waits")

        tab("Settings")
        let notice = app.staticTexts["publications-waiting"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "Settings should say that saves are waiting: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["publications-account"].label.contains("qa"), "The notice names the signed-in account")
        // Saving again is not recovery: the held save could still replace what it sends.
        select(app.buttons["send-listening"])
        try await Task.sleep(nanoseconds: 3_000_000_000)
        var sessions = try await observations().localSessions.filter { $0.libraryItemId == "book-0" }
        XCTAssertTrue(sessions.isEmpty, "Later listening was sent while the held save could still be applied")
        XCTAssertFalse(app.buttons["confirm-server-restarted"].exists, "A restart can only be confirmed after it was asked for")
        capture("publications-waiting")

        let request = app.buttons["request-server-restart"]
        select(request)
        let confirm = app.buttons["confirm-server-restarted"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["restart-instructions"].exists)
        XCTAssertTrue(hasFocus(confirm), "Focus moves to the next step")
        capture("publications-restart-requested")

        // The request survives a relaunch; nothing is sent meanwhile.
        app.terminate()
        launch(reset: false)
        waitForHome()
        tab("Settings")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The requested restart is still waiting for confirmation after a relaunch")

        try await Fixture.restartServer()
        let restarted = try await observations()
        XCTAssertEqual(restarted.serverRestarts.map(\.endedHandlers), [1], "Precondition: the restart ended the held save")
        select(confirm)
        for _ in 0..<30 where sessions.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            sessions = try await observations().localSessions.filter { $0.libraryItemId == "book-0" }
        }
        let sent = try XCTUnwrap(sessions.first, "The listening that waited was not sent after the confirmed restart")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertGreaterThanOrEqual(Int(sent.currentTime), listenedTo - 1)
        XCTAssertGreaterThan(sent.timeListening, 4, "Listening from both plays is kept")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        await fulfillment(of: [gone], timeout: 10)
        XCTAssertFalse(confirm.exists)
        let reported = try await observations().reports.count

        app.terminate()
        launch(reset: false)
        waitForHome()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let after = try await observations().reports.count
        XCTAssertEqual(after, reported, "A delivered save must not be sent again")
        tab("Settings")
        XCTAssertTrue(app.buttons["send-listening"].waitForExistence(timeout: 10))
        XCTAssertFalse(notice.exists)
    }
}
