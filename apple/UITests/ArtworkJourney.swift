import XCTest

@MainActor final class ArtworkJourney: NativeJourney {
    func testLoadedSquareAndPortraitCoversStayInsidePhoneGridColumns() async throws {
        try await FixtureControl.configure("large-cover-art")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Settings"].tap(); app.buttons["theme-black"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        let first = app.buttons["book-book-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        for _ in 0..<20 {
            if try await fixtureRequests().contains(where: { $0.path == "/api/items/book-0/cover" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        capture("Loaded cover grid")
        let screen = app.windows.firstMatch.frame
        let second = app.buttons["book-book-1"]
        XCTAssertTrue(second.exists)
        XCTAssertGreaterThanOrEqual(first.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(second.frame.maxX, screen.maxX)
        XCTAssertLessThan(first.frame.width, screen.width * 0.55)
        XCTAssertLessThan(second.frame.width, screen.width * 0.55)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1, "Different title and author lengths must not stagger grid rows")
        XCTAssertLessThanOrEqual(first.frame.maxX, second.frame.minX, "Loaded covers must not overlap their neighboring card")
        first.tap()
        XCTAssertTrue(app.staticTexts["Narrated by QA Narrator"].waitForExistence(timeout: 5))
        capture("Loaded cover details")
    }
}
