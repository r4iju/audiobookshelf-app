import XCTest

@MainActor final class OfflineJourney: NativeJourney {
    func testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let download = app.buttons["Download for offline"]
        XCTAssertTrue(download.waitForExistence(timeout: 3))
        guard download.exists else { return }
        download.tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Open downloads"].waitForExistence(timeout: 10))
        app.buttons["Open downloads"].tap()
        app.buttons["offline-book-0"].tap()
        app.buttons["Play offline"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 3))
        app.buttons["mini-pause-playback"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["Forward 10 seconds"].tap()
        XCTAssertTrue(app.staticTexts["File 2 of 2"].waitForExistence(timeout: 5))
        let position = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertGreaterThanOrEqual(position, 16)
        app.terminate()
        app.launch()
        app.buttons["Open downloads"].tap()
        app.buttons["offline-book-0"].tap()
        app.buttons["Play offline"].tap()
        app.buttons["mini-pause-playback"].tap()
        app.buttons["mini-player"].tap()
        let restored = try XCTUnwrap(Int(bookElapsed(app).label.split(separator: " ").first ?? ""))
        XCTAssertGreaterThanOrEqual(restored, position)
        try await FixtureControl.configure("baseline")
        app.buttons["Close playback"].tap()
        app.terminate()
        app.launch()
        let reports = try await fixtureObservations().localSessions
        XCTAssertTrue(reports.contains { $0.currentTime >= Double(position) && $0.timeListening > 0 })
    }
    func testNewerRemoteRewindBecomesTheNextOfflineResumeWithoutRedownloading() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        let originalDownloads = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }.count
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["Open downloads"].waitForExistence(timeout: 10))
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["Play offline"].tap()
        app.buttons["mini-pause-playback"].tap(); app.buttons["mini-player"].tap()
        app.buttons["Forward 10 seconds"].tap()
        app.buttons["Close playback"].tap()
        app.terminate()
        try await FixtureControl.configure("remote-rewind")
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["Play offline"].tap()
        app.buttons["mini-player"].tap(); app.buttons["pause-playback"].tap()
        let position = try XCTUnwrap(Int(app.staticTexts["playback-elapsed"].label.split(separator: " ").first ?? ""))
        XCTAssertLessThanOrEqual(position, 5, "A newer remote rewind must replace the previous local position")
        let downloads = try await fixtureRequests().filter { $0.path.hasSuffix("/download") }
        XCTAssertEqual(downloads.count, originalDownloads, "Valid offline files must be reused")
    }

    func testSuccessfulHTTPErrorPageIsRejectedAndRetryRecoversTheDownload() async throws {
        try await FixtureControl.configure("download-error-page")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["Retry download"].waitForExistence(timeout: 45), "An HTTP 200 error page must not become playable offline content")
        guard app.buttons["Retry download"].exists else { return }
        XCTAssertFalse(app.buttons["offline-book-0"].exists)
        try await FixtureControl.configure("baseline")
        app.buttons["Retry download"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 5))
    }

}
