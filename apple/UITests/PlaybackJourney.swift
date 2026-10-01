import XCTest

@MainActor final class PlaybackJourney: NativeJourney {
    func testPauseDuringSessionPreparationPreventsAutoplay() async throws {
        try await FixtureControl.configure("slow-session")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        let pause = app.buttons["mini-pause-playback"]
        XCTAssertTrue(pause.waitForExistence(timeout: 2))
        guard pause.exists else { return }
        pause.tap()
        app.buttons["mini-player"].tap()
        let elapsed = app.staticTexts["playback-elapsed"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "6 sec"), object: elapsed)
        await fulfillment(of: [restored], timeout: 10)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(elapsed.label, "6 sec")
        XCTAssertTrue(app.buttons["resume-playback"].exists)
    }

    func testMissingMediaShowsRecoveryOnBookDetails() async throws {
        try await FixtureControl.configure("no-audio")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.staticTexts["This item has no playable audio."].waitForExistence(timeout: 5))
    }

    func testLatestSeekWinsWhileNextFileIsPreparing() async throws {
        try await FixtureControl.configure("slow-audio")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        app.buttons["pause-playback"].tap()
        // Force a different file to load, then replace that pending seek.
        app.buttons["Back 30 seconds"].tap()
        let atStart = NSPredicate(format: "label == %@", "0 sec")
        let initial = XCTNSPredicateExpectation(predicate: atStart, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [initial], timeout: 10)
        app.buttons["Forward 30 seconds"].tap()
        app.buttons["Back 30 seconds"].tap()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Paused"), object: app.staticTexts["playback-status"])
        await fulfillment(of: [settled], timeout: 10)
        let position = app.staticTexts["playback-elapsed"]
        let latest = XCTNSPredicateExpectation(predicate: atStart, object: position)
        await fulfillment(of: [latest], timeout: 10)
        XCTAssertTrue(app.buttons["resume-playback"].exists)
    }

    func testRealAudioCrossesFilesAndContinuesAfterLeavingDetails() async throws {
        let cursor = try await fixtureRequests().count
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let play = app.buttons["play-book"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        guard play.exists else { return }
        play.tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.staticTexts["File 2 of 2"].waitForExistence(timeout: 12))
        app.buttons["pause-playback"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 5))
        let requests = try await fixtureRequests()
        let media = requests.dropFirst(cursor)
        XCTAssertTrue(media.contains { $0.path == "/audio/0" })
        XCTAssertTrue(media.contains { $0.path == "/audio/1" })
        var reports = try await fixtureObservations().reports
        for _ in 0..<10 {
            if reports.contains(where: { $0.currentTime >= 8 && $0.timeListened > 0 }) { break }
            try await Task.sleep(nanoseconds: 200_000_000)
            reports = try await fixtureObservations().reports
        }
        XCTAssertTrue(reports.contains { $0.currentTime >= 8 && $0.currentTime < 20 && $0.timeListened > 0 })
    }
}
