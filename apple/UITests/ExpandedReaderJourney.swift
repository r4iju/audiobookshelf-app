import XCTest

@MainActor final class ExpandedReaderJourney: NativeJourney {
    func testUnknownPDFLocationStaysIntactUntilReaderNavigates() async throws {
        try await FixtureControl.configure("pdf-unknown")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap(); app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reading-location-warning"].exists)
        let observed = try await fixtureObservations()
        XCTAssertTrue(observed.readingProgress.isEmpty)
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 4"].waitForExistence(timeout: 5))
    }
    func testUnknownEPUBLocationStaysIntactUntilReaderNavigates() async throws {
        try await FixtureControl.configure("epub-unknown")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap(); app.buttons["Read EPUB"].tap()
        XCTAssertTrue(app.staticTexts["First passage by the window."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["reading-location-warning"].exists)
        let observed = try await fixtureObservations()
        XCTAssertTrue(observed.readingProgress.isEmpty, "Opening must not replace an unknown location")
        app.buttons["Contents"].tap(); app.buttons["Second chapter"].tap()
        let resumed = app.staticTexts["Second passage beneath the stars."].waitForExistence(timeout: 10)
        capture("unknown-epub-after-navigation")
        XCTAssertTrue(resumed, app.debugDescription)
    }
    func testCBZPagesResumeOffline() async throws { try await comic("cbz") }
    func testCBRPagesResumeOffline() async throws { try await comic("cbr") }
    func testMOBIPassageAndTypographyResumeOffline() async throws { try await textBook("mobi") }
    func testAZW3PassageAndTypographyResumeOffline() async throws { try await textBook("azw3") }
    private func textBook(_ format: String) async throws {
        try await FixtureControl.configure(format + "-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap()
        let read = app.buttons["Read " + format.uppercased()]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        guard read.exists else { return }
        read.tap()
        XCTAssertTrue(app.staticTexts["Field chapter 1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Contents"].tap(); app.buttons["Field chapter 3"].tap()
        XCTAssertTrue(app.staticTexts["Field chapter 3"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Reading settings"].tap()
        app.buttons["reader-theme"].tap(); app.buttons["Light"].tap(); app.buttons["Done"].tap()
        capture(format + "-third-chapter")
        app.buttons["Close reader"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.staticTexts["Field chapter 3"].firstMatch.waitForExistence(timeout: 15), "The authored passage must return offline after relaunch")
        app.buttons["Reading settings"].tap()
        XCTAssertTrue(app.buttons["reader-theme"].label.contains("Light"))
    }
    private func comic(_ format: String) async throws {
        try await FixtureControl.configure(format + "-reader")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap()
        let read = app.buttons["Read " + format.uppercased()]
        XCTAssertTrue(read.waitForExistence(timeout: 5), "The primary comic must be available to read")
        guard read.exists else { return }
        read.tap()
        XCTAssertTrue(app.images["Panel 1.png"].waitForExistence(timeout: 15), "A decoded panel must be presented")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.images["Panel 2.png"].waitForExistence(timeout: 5), "Page numbers must sort numerically")
        app.buttons["Contents"].tap(); app.buttons["Panel 10.png"].tap()
        XCTAssertTrue(app.images["Panel 10.png"].waitForExistence(timeout: 5))
        capture(format + "-third-panel")
        app.buttons["Close reader"].tap()
        app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap(); app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-0"].waitForExistence(timeout: 45))
        try await FixtureControl.configure("offline-library")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["Open downloads"].tap(); app.buttons["offline-book-0"].tap(); app.buttons["read-downloaded-ebook"].tap()
        XCTAssertTrue(app.images["Panel 10.png"].waitForExistence(timeout: 15), "The actual saved panel must reopen offline after relaunch")
    }
}
