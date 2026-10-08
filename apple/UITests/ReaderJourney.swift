import XCTest

@MainActor final class ReaderJourney: NativeJourney {
    func testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage() async throws {
        try await downloadedReaderWithUnreadableStorage(mode: "epub-reader", content: "First passage by the window.")
    }
    func testDownloadedPDFRemainsReadableWithUnreadableProgressStorage() async throws {
        try await downloadedReaderWithUnreadableStorage(mode: "pdf-reader", content: "Page 1 of 4")
    }
    private func downloadedReaderWithUnreadableStorage(mode: String, content: String) async throws {
        try await FixtureControl.configure(mode)
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons[mode == "epub-reader" ? "Read EPUB" : "Read PDF"].tap()
        XCTAssertTrue(app.staticTexts[content].waitForExistence(timeout: 10))
        for _ in 0..<30 {
            if try await !fixtureObservations().readingProgress.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        app.buttons["Close reader"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        let requestsBeforeRelaunch = try await fixtureRequests().filter { $0.method == "PATCH" && $0.path.contains("/progress/") }.count
        app.terminate(); app.launchArguments = ["--unreadable-preview-reading"]; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts[content].waitForExistence(timeout: 10), "A damaged reading journal must not prevent opening a valid downloaded book")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "could not be restored")).firstMatch.exists)
        let requestsAfterRelaunch = try await fixtureRequests().filter { $0.method == "PATCH" && $0.path.contains("/progress/") }.count
        XCTAssertEqual(requestsAfterRelaunch, requestsBeforeRelaunch)
    }
    func testUnreadableReadingStorageRemainsVisibleAcrossRelaunch() async throws {
        try await FixtureControl.configure("epub-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false, arguments: ["--unreadable-preview-reading"])
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        let failure = app.staticTexts["reading-save-error"]
        XCTAssertTrue(failure.waitForExistence(timeout: 3))
        guard failure.exists else { return }
        XCTAssertTrue(failure.label.contains("could not be restored"))
        app.buttons["Next page"].tap()
        let observations = try await fixtureObservations()
        XCTAssertTrue(observations.readingProgress.isEmpty, "Unreadable progress storage must not publish unsaved reading")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["reading-save-error"].waitForExistence(timeout: 10), "The original unreadable data must remain available for recovery")
    }
    func testEPUBVolumeNavigationPreferencesSurviveRelaunch() async throws {
        try await FixtureControl.configure("epub-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        app.buttons["Reading settings"].tap()
        let mode = app.buttons["reader-volume-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 3))
        guard mode.exists else { return }
        mode.tap(); app.buttons["Mirrored"].tap()
        let listening = app.switches["Volume navigation while listening"]
        listening.switches.firstMatch.tap(); XCTAssertEqual(listening.value as? String, "1")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        app.buttons["Reading settings"].tap()
        XCTAssertTrue(app.buttons["reader-volume-mode"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader-volume-mode"].label.contains("Mirrored"))
        XCTAssertEqual(app.switches["Volume navigation while listening"].value as? String, "1")
    }
    func testRestoredEPUBPassagePublishesCorrectedPercentage() async throws {
        try await FixtureControl.configure("epub-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        app.buttons["Contents"].tap(); app.buttons["Second chapter"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
        for _ in 0..<30 {
            if (try await fixtureObservations().readingProgress.first?.ebookProgress ?? 0) > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await FixtureControl.configure("epub-zero-percentage")
        app.terminate()
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
        var fraction = 0.0
        for _ in 0..<30 {
            fraction = try await fixtureObservations().readingProgress.first?.ebookProgress ?? 0
            if fraction > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThan(fraction, 0, "Restoring the same CFI must correct its actual calculated reading percentage")
    }
    func testEPUBPublisherStylesImagesAndSwipeNavigation() async throws {
        try await FixtureControl.configure("epub-styled")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Publisher hidden text"].exists, "Archived publisher CSS must apply to the rendered chapter")
        XCTAssertTrue(app.images["Illustration from the publisher"].exists)
        app.webViews["epub-document"].swipeLeft()
        var location = ""
        for _ in 0..<50 {
            location = try await fixtureObservations().readingProgress.first?.ebookLocation ?? ""
            if location.contains("[second]") { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(location.contains("[second]"), "Swiping must advance the actual rendered and published passage")
    }
    func testEPUBReadingWhileListeningRetainsAwakePreference() async throws {
        try await FixtureControl.configure("epub-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 10))
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label) else { return false }
            return seconds >= 10
        }, object: app.staticTexts["reader-audio-elapsed"])
        await fulfillment(of: [advanced], timeout: 10)
        app.buttons["reader-pause-playback"].tap()
        app.buttons["Reading settings"].tap()
        let awake = app.switches["Keep screen awake"]
        XCTAssertTrue(awake.waitForExistence(timeout: 3))
        guard awake.exists else { return }
        awake.switches.firstMatch.tap(); XCTAssertEqual(awake.value as? String, "1")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Contents"].tap(); app.buttons["Second chapter"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
        app.buttons["Close reader"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
        app.buttons["Reading settings"].tap()
        XCTAssertEqual(app.switches["Keep screen awake"].value as? String, "1")
    }
    func testInvalidEPUBRecoveryOpensLongDocument() async throws {
        try await FixtureControl.configure("epub-invalid")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 10))
        guard app.buttons["Try again"].exists else { print(app.debugDescription); return }
        try await FixtureControl.configure("epub-long")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 15))
        app.buttons["Contents"].tap(); app.buttons["Second chapter"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 500_000_000)
        let prior = try await fixtureObservations().readingProgress.first?.ebookLocation
        app.buttons["Next page"].tap()
        var current = prior
        for _ in 0..<50 {
            current = try await fixtureObservations().readingProgress.first?.ebookLocation
            if current != prior { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotEqual(current, prior, "Page navigation must advance actual long-document content")
        capture("Native EPUB long document after page turn")
    }
    func testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch() async throws {
        try await FixtureControl.configure("epub-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let read = app.buttons["Read EPUB"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        guard read.exists else { return }
        read.tap()
        let first = app.staticTexts["First passage by the window."].waitForExistence(timeout: 10)
        XCTAssertTrue(first)
        guard first else { print(app.debugDescription); return }
        app.buttons["Contents"].tap(); app.buttons["Second chapter"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
        var location: String?
        for _ in 0..<30 {
            location = try await fixtureObservations().readingProgress.first?.ebookLocation
            if location?.hasPrefix("epubcfi(") == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(location?.hasPrefix("epubcfi(") == true, "EPUB progress must identify the actual passage")
        app.buttons["Close reader"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10))
    }
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
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
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
        let initialRequestCount = try await fixtureRequests().count
        app.buttons["Next page"].tap()
        var issued = false
        for _ in 0..<30 {
            issued = try await fixtureRequests().dropFirst(initialRequestCount).contains { $0.method == "PATCH" && $0.path == "/api/me/progress/book-0" && $0.ebookLocation == "2" }
            if issued { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(issued, "The older page must be in flight before advancing")
        guard issued else { return }
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].exists)
        if mode != "pdf-delayed" {
            // The older page reached the server with its answer lost and may still be applied, so the newer page
            // stays on this device until a restart asked for after it is confirmed.
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let sent = try await fixtureRequests().dropFirst(initialRequestCount)
            XCTAssertFalse(sent.contains { $0.ebookLocation == "3" }, "The newer page was sent while the older one could still be applied")
            let applied = try await fixtureObservations().readingProgress.first?.ebookLocation
            XCTAssertEqual(applied, "2", "Precondition: the server applied the older page")
            app.buttons["Close reader"].tap()
            let restart = app.buttons["restart-server"]
            XCTAssertTrue(restart.waitForExistence(timeout: 10), "Open details should offer a server restart once a save got no answer")
            restart.tap()
            let confirm = app.alerts.buttons["Server restarted"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            try await FixtureControl.restart()
            confirm.tap()
            app.buttons["Read PDF"].tap()
            XCTAssertTrue(app.staticTexts["Page 3 of 4"].waitForExistence(timeout: 10))
        }
        if mode == "pdf-double-failure" {
            var rejected = false
            for _ in 0..<60 {
                rejected = try await fixtureRequests().dropFirst(initialRequestCount).contains { $0.ebookLocation == "3" && $0.applied == false }
                if rejected { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertTrue(rejected, "The newer page retry must be rejected before it reaches server progress")
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
        app.buttons["Page actions"].tap()
        XCTAssertEqual(app.switches["Continuous"].value as? String, "0")
        app.switches["Continuous"].switches.firstMatch.tap()
        XCTAssertEqual(app.switches["Continuous"].value as? String, "1")
        capture("Native PDF continuous reading")
        app.buttons["Done"].tap()
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].exists)
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Close reader"].exists)
        app.buttons["Close reader"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of 4"].waitForExistence(timeout: 10))
        app.buttons["Page actions"].tap()
        XCTAssertEqual(app.switches["Continuous"].value as? String, "1")
        app.buttons["Done"].tap()
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
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
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
        app.buttons["Page actions"].tap()
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
        app.buttons["Page actions"].tap()
        app.buttons["Rotate page"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists)
        app.buttons["Done"].tap()
        app.buttons["Close reader"].tap()
        app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 10))
        app.buttons["Page actions"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists)
        app.buttons["Done"].tap()
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
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        let originals = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }.count
        app.buttons["Library"].tap()
        try await FixtureControl.configure("pdf-rotated")
        app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["Read PDF"].waitForExistence(timeout: 3))
        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        app.buttons["Page actions"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 90°"].exists, "Document-authored page rotation must be preserved")
        app.buttons["Rotate page"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 180°"].exists)
        app.buttons["Done"].tap()
        app.buttons["Close reader"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        app.buttons["offline-book-0"].tap()
        XCTAssertTrue(app.buttons["read-downloaded-ebook"].waitForExistence(timeout: 5), "Existing audio downloads must be able to gain their ebook")
        guard app.buttons["read-downloaded-ebook"].exists else { return }
        app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        app.buttons["Page actions"].tap()
        XCTAssertTrue(app.staticTexts["Rotation 180°"].exists)
        let files = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }
        XCTAssertEqual(files.count, originals + 1, "Only the new ebook should download")
    }

}
