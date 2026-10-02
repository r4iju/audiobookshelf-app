import XCTest

@MainActor final class ListeningControlsJourney: NativeJourney {
    func testTimerAdjustmentChangesActualStopAndResetKeepsOriginalDuration() async throws {
        let app = try await openPlayer()
        app.buttons["Sleep timer"].tap()
        app.textFields["timer-seconds"].tap()
        app.textFields["timer-seconds"].typeText("3")
        startTimer(app)
        waitForPanelToClose(app, "Sleep")
        app.buttons["Sleep timer"].tap()
        let extend = app.buttons["Add 5 minutes"]
        XCTAssertTrue(extend.waitForExistence(timeout: 3))
        guard extend.exists else { return }
        extend.tap()
        app.navigationBars["Sleep"].buttons["Done"].tap()
        waitForPanelToClose(app, "Sleep")
        app.buttons["resume-playback"].tap()
        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertTrue(app.buttons["pause-playback"].exists)
        app.buttons["Sleep timer"].tap()
        app.buttons["Reset timer"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 7))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep in ")).firstMatch.exists)
    }

    func testResumeRewindsAfterAPauseAndCanBeDisabledPersistently() async throws {
        let app = try await openPlayer()
        let before = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        try await Task.sleep(nanoseconds: 11_000_000_000)
        app.buttons["resume-playback"].tap()
        app.buttons["pause-playback"].tap()
        let rewound = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertLessThan(rewound, before)
        app.buttons["Playback settings"].tap()
        let rewind = app.switches["Rewind after a pause"]
        XCTAssertTrue(rewind.waitForExistence(timeout: 3))
        guard rewind.exists else { return }
        rewind.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(rewind.value as? String, "0")
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["pause-playback"].tap()
        app.buttons["Playback settings"].tap()
        XCTAssertEqual(app.switches["Rewind after a pause"].value as? String, "0")
    }

    func testDeletingFractionalBookmarkPreservesItsIntegerNeighbor() async throws {
        try await FixtureControl.configure("baseline")
        for (time, title) in [(6.0, "Whole second"), (6.5, "Half second")] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs/api/me/item/book-0/bookmark")!)
            request.httpMethod = "POST"
            request.setValue("Bearer fresh", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["time": time, "title": title])
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["pause-playback"].tap()
        app.buttons["Bookmarks"].tap()
        XCTAssertTrue(app.buttons["Half second"].waitForExistence(timeout: 5))
        app.buttons["Delete Half second"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Half second"])
        await fulfillment(of: [deleted], timeout: 5)
        XCTAssertTrue(app.buttons["Whole second"].exists)
    }

    func testDisablingAnActiveSleepFadeRestoresActualAudioVolume() async throws {
        let app = try await openPlayer()
        app.buttons["Sleep timer"].tap()
        app.textFields["timer-seconds"].tap()
        app.textFields["timer-seconds"].typeText("10")
        startTimer(app)
        waitForPanelToClose(app, "Sleep")
        app.buttons["resume-playback"].tap()
        app.buttons["Sleep timer"].tap()
        let volume = app.staticTexts["fade-volume"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        XCTAssertNotEqual(volume.label, "Audio volume: 100%")
        let fade = app.switches["Fade audio in the last minute"]
        fade.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(fade.value as? String, "0")
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Audio volume: 100%"), object: volume)
        await fulfillment(of: [restored], timeout: 3)
    }
    /// UI tests run with a hardware keyboard attached, so after typing, iPadOS minimizes the visible software keyboard on the
    /// next touch and the Sleep sheet re-centres under it, losing the tap on Start. Return ends editing first, as it does for a
    /// person typing on that keyboard, so Start is tapped where it is.
    private func startTimer(_ app: XCUIApplication) {
        app.textFields["timer-seconds"].typeText("\n")
        let keyboard = app.keyboards.firstMatch
        let hidden = expectation(for: NSPredicate { _, _ in !keyboard.exists || keyboard.frame.height == 0 }, evaluatedWith: keyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 5), .completed, "Return hides the software keyboard")
        app.buttons["Start timer"].tap()
    }
    private func openPlayer() async throws -> XCUIApplication {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        app.buttons["pause-playback"].tap()
        return app
    }

    func testChapterSeekAndSpeedSurviveSessionRestoration() async throws {
        let app = try await openPlayer()
        // Resuming after a pause of ten seconds or more rewinds, and the iPad steps to here take that long.
        playerSettings(app, [("Rewind after a pause", false)])
        let chapters = app.buttons["Chapters"]
        XCTAssertTrue(chapters.waitForExistence(timeout: 3))
        guard chapters.exists else { return }
        chapters.tap()
        app.buttons["chapter-1"].tap()
        waitForPanelToClose(app, "Chapters")
        XCTAssertTrue(app.staticTexts["File 2 of 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(bookElapsed(app).label, "8 sec")
        XCTAssertEqual(app.staticTexts["chapter-elapsed"].label, "0 sec of 12 sec")
        app.buttons["Playback speed"].tap()
        app.buttons["speed-2"].tap()
        waitForPanelToClose(app, "Speed")
        app.buttons["resume-playback"].tap()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        app.buttons["pause-playback"].tap()
        playerSettings(app, [("scale-elapsed-setting", false)])
        let seconds = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertGreaterThanOrEqual(seconds, 12)
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.staticTexts["2×"].waitForExistence(timeout: 5))
        capture("native-modern-player")
    }

    func testConfiguredSkipIntervalsSeekAcrossFilesAndPersist() async throws {
        let app = try await openPlayer()
        let settings = app.buttons["Playback settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        guard settings.exists else { return }
        settings.tap()
        app.buttons["Forward interval"].tap()
        app.buttons["5 seconds"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let forward = app.buttons["Forward 5 seconds"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        forward.tap()
        XCTAssertTrue(app.staticTexts["File 2 of 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(bookElapsed(app).label, "\(before + 5) sec")
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["Forward 5 seconds"].waitForExistence(timeout: 5))
    }

    func testBookmarkCreateEditJumpAndDeletePersistOnServer() async throws {
        let app = try await openPlayer()
        let bookmarks = app.buttons["Bookmarks"]
        XCTAssertTrue(bookmarks.waitForExistence(timeout: 3))
        guard bookmarks.exists else { return }
        bookmarks.tap()
        let title = app.textFields["bookmark-title"]
        title.tap()
        title.typeText("A passage")
        app.buttons["Save bookmark"].tap()
        XCTAssertTrue(app.buttons["A passage"].waitForExistence(timeout: 5))
        app.buttons["Edit A passage"].tap()
        title.tap()
        title.typeText(" revised")
        app.buttons["Save bookmark"].tap()
        XCTAssertTrue(app.buttons["A passage revised"].waitForExistence(timeout: 5))
        app.navigationBars["Bookmarks"].buttons["Done"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["pause-playback"].tap()
        app.buttons["Bookmarks"].tap()
        app.buttons["A passage revised"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 5))
        app.buttons["Bookmarks"].tap()
        app.buttons["Delete A passage revised"].tap()
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].waitForExistence(timeout: 5))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/me/item/book-0/bookmark" })
    }

    func testShortSleepTimerActuallyStopsAndPersistsPositionAfterLeavingPlayer() async throws {
        let app = try await openPlayer()
        let timer = app.buttons["Sleep timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        guard timer.exists else { return }
        timer.tap()
        let duration = app.textFields["timer-seconds"]
        duration.tap()
        duration.typeText("3")
        startTimer(app)
        app.buttons["resume-playback"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["mini-resume-playback"].waitForExistence(timeout: 8))
        app.buttons["mini-player"].tap()
        let stopped = app.staticTexts["playback-elapsed"].label
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(app.staticTexts["playback-elapsed"].label, stopped)
        let reports = try await fixtureObservations().reports
        XCTAssertTrue(reports.contains { $0.currentTime > 6 && $0.currentTime < 16 && $0.timeListened > 0 })
    }

    func testSeekingPastChapterSleepBoundaryStopsAudioInsteadOfLeavingTimerStranded() async throws {
        let app = try await openPlayer()
        app.buttons["Chapters"].tap()
        app.buttons["chapter-0"].tap()
        XCTAssertEqual(app.staticTexts["playback-elapsed"].label, "0 sec")
        app.buttons["Sleep timer"].tap()
        app.buttons["End of chapter"].tap()
        app.buttons["resume-playback"].tap()
        app.buttons["Forward 10 seconds"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Sleep at chapter end"].exists)
        let stopped = app.staticTexts["playback-elapsed"].label
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(app.staticTexts["playback-elapsed"].label, stopped)
    }
}
