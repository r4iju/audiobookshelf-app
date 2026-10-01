import XCTest

@MainActor final class ReaderJourney: NativeJourney {
    func testSupplementaryPDFDownloadsAndRetainsItsOwnPage() async throws {
        try await FixtureControl.configure("pdf-remote")
        try await FixtureControl.configure("pdf-supplementary")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let read = app.buttons["Read Listening notes.pdf"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        guard read.exists else { return }
        read.tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 2"].waitForExistence(timeout: 10))
        app.buttons["Next page"].tap(); app.buttons["Close reader"].tap()
        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 4 of 4"].waitForExistence(timeout: 10), "Supplementary pages must not replace primary reading progress")
        app.buttons["Close reader"].tap(); app.buttons["Download Listening notes.pdf"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0-notes"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0-notes"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.otherElements["pdf-document"].value as? String)?.contains("Listening notes - Passage 2") == true)
    }
    func testNewerPageSurvivesAnOlderPublicationInFlight() async throws {
        try await verifyNewerPageDuringPublication(mode: "pdf-delayed")
    }
    func testNewerPageSurvivesAnAppliedPublicationWithLostResponse() async throws {
        try await verifyNewerPageDuringPublication(mode: "pdf-lost-ack")
    }
    func testNewerPageSurvivesLostAcknowledgmentThenRejectedRetry() async throws {
        try await verifyNewerPageDuringPublication(mode: "pdf-double-failure")
    }
    private func verifyNewerPageDuringPublication(mode: String) async throws {
        try await FixtureControl.configure(mode)
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        app.buttons["Next page"].tap()
        var issued = false
        for _ in 0..<30 {
            issued = try await fixtureRequests().contains { $0.method == "PATCH" && $0.path == "/api/me/progress/book-0" }
            if issued { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(issued, "The older page must be in flight before advancing")
        guard issued else { return }
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].exists)
        if mode == "pdf-double-failure" {
            var attempts = 0
            for _ in 0..<60 {
                attempts = try await fixtureRequests().filter { $0.method == "PATCH" && $0.path == "/api/me/progress/book-0" }.count
                if attempts >= 2 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(attempts, 2)
            try await Task.sleep(nanoseconds: 500_000_000)
            app.buttons["Close reader"].tap(); app.buttons["Read PDF"].tap()
            XCTAssertTrue(app.staticTexts["Page 3 of 4"].waitForExistence(timeout: 10))
        }
        var latest: String?
        for _ in 0..<50 {
            latest = try await fixtureObservations().readingProgress.first?.ebookLocation
            if latest == "3" { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(latest, "3", "An older publication's echo must not replace the newer local page")
        app.buttons["Close reader"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].waitForExistence(timeout: 10))
    }
    func testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference() async throws {
        try await FixtureControl.configure("pdf-audio")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reader-pause-playback"].waitForExistence(timeout: 3), "Listening controls must remain reachable while reading")
        guard app.buttons["reader-pause-playback"].exists else { return }
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label) else { return false }
            return seconds >= 10
        }, object: app.staticTexts["reader-audio-elapsed"])
        await fulfillment(of: [advanced], timeout: 10)
        app.buttons["Next page"].tap(); app.buttons["reader-pause-playback"].tap()
        XCTAssertEqual(app.switches["Continuous"].value as? String, "0")
        app.switches["Continuous"].tap()
        XCTAssertEqual(app.switches["Continuous"].value as? String, "1")
        capture("Native PDF continuous reading")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].exists)
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Close reader"].exists)
        app.buttons["Close reader"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["Continuous"].value as? String, "1")
        XCTAssertTrue((app.otherElements["pdf-document"].value as? String)?.contains("Passage 3") == true)
        let observed = try await fixtureObservations()
        XCTAssertTrue(observed.localSessions.contains { $0.timeListening > 0 && $0.currentTime >= 10 })
    }
    func testFirstOfflineOpeningUsesReadingPositionCapturedDuringDownload() async throws {
        try await FixtureControl.configure("pdf-remote")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 4 of 4"].waitForExistence(timeout: 10), "Download must retain server reading progress before the first offline opening")
    }
    func testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect() async throws {
        try await FixtureControl.configure("pdf-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["Play offline"].tap()
        app.buttons["mini-pause-playback"].tap(); app.buttons["mini-player"].tap()
        app.buttons["Forward 10 seconds"].tap()
        XCTAssertTrue(app.staticTexts["File 2 of 2"].waitForExistence(timeout: 5))
        let position = try XCTUnwrap(Int(app.staticTexts["playback-elapsed"].label.split(separator: " ").first ?? ""))
        app.buttons["Done"].tap()
        try await FixtureControl.configure("offline-progress")
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].exists)
        let unpublished = try await fixtureObservations().readingProgress
        XCTAssertTrue(unpublished.isEmpty, "Page publication must wait for unsent audio, rather than advancing its shared timestamp")
        try await FixtureControl.configure("pdf-reader")
        app.buttons["Close reader"].tap(); app.navigationBars.buttons["BackButton"].tap(); app.buttons["Done"].tap()
        app.buttons["mini-player"].tap(); app.buttons["Close playback"].tap()
        for _ in 0..<30 {
            if !(try await fixtureObservations().readingProgress).isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let observed = try await fixtureObservations()
        let published = try XCTUnwrap(observed.readingProgress.first)
        XCTAssertEqual(published.ebookLocation, "2")
        XCTAssertGreaterThanOrEqual(published.currentTime ?? 0, Double(position))
        app.terminate(); app.launch()
        app.buttons["book-book-0"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 10))
    }
    func testInvalidPDFRecoveryAndLongDocumentPageNavigation() async throws {
        try await FixtureControl.configure("pdf-invalid")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 10))
        try await FixtureControl.configure("pdf-long")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 120"].waitForExistence(timeout: 10))
        let page = app.textFields["reader-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 3), "Long documents need direct page navigation")
        guard page.exists else { return }
        page.tap(); page.typeText("119")
        app.buttons["Go to page"].tap()
        XCTAssertTrue(app.staticTexts["Page 119 of 120"].waitForExistence(timeout: 3))
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 120 of 120"].exists)
        XCTAssertFalse(app.buttons["Next page"].isEnabled)
        app.buttons["Close reader"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 120 of 120"].waitForExistence(timeout: 10))
    }
    func testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch() async throws {
        try await FixtureControl.configure("pdf-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let read = app.buttons["Read PDF"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        guard read.exists else { return }
        read.tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["pdf-document"].exists)
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 3))
        app.buttons["Rotate page"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists)
        app.buttons["Close reader"].tap()
        app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists)
        app.terminate(); app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 10))
    }
    func testNewerRemotePDFPageWinsAfterOfflineReconnection() async throws {
        try await FixtureControl.configure("pdf-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        app.buttons["Next page"].tap(); app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].exists)
        app.buttons["Close reader"].tap(); app.terminate()
        try await FixtureControl.configure("pdf-remote")
        app.launch()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 4 of 4"].waitForExistence(timeout: 10), "Newer reading on another client must survive reconnect")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native PDF remote page"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        let originals = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }.count
        app.buttons["Done"].tap()
        try await FixtureControl.configure("pdf-rotated")
        app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["Read PDF"].waitForExistence(timeout: 3))
        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists, "Document-authored page rotation must be preserved")
        app.buttons["Rotate page"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 180°"].exists)
        app.buttons["Close reader"].tap(); app.buttons["Download for offline"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        app.buttons["offline-book-0"].tap()
        XCTAssertTrue(app.buttons["read-downloaded-ebook"].waitForExistence(timeout: 5), "Existing audio downloads must be able to gain their ebook")
        guard app.buttons["read-downloaded-ebook"].exists else { return }
        app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Rotation 180°"].exists)
        let files = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }
        XCTAssertEqual(files.count, originals + 1, "Only the new ebook should download")
    }

}
