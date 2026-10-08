import XCTest
import UIKit

@MainActor final class ShellJourney: NativeJourney {
    private func destination(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let tab = app.buttons[name].firstMatch
        return tab.exists ? tab : app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    func testDestinationsKeepLibrarySelectionAndDetailsWhileBrowsing() async throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        capture("Before or after native shell")
        let library = destination("Library", in: app)
        XCTAssertTrue(library.waitForExistence(timeout: 5), "Library must be a visible main destination")
        guard library.exists else { return }
        library.tap()
        XCTAssertTrue(app.buttons["Collections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Playlists"].exists)
        app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 5))
        capture("Native detail")
        destination("Downloads", in: app).tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        destination("Settings", in: app).tap()
        XCTAssertTrue(app.buttons["language-settings"].waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 5), "Switching destinations retains the open Library detail")
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.staticTexts["Podcasts"].firstMatch.waitForExistence(timeout: 5))
        destination("Search", in: app).tap()
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5), "Search uses the native system field")
        query.tap(); query.typeText("Quiet Evening")
        capture("Native search keyboard")
        query.typeText("\n")
        XCTAssertTrue(app.buttons["search-episode-episode"].waitForExistence(timeout: 10))
        destination("Listen Now", in: app).tap()
        XCTAssertTrue(app.navigationBars["Listen Now"].waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(app.staticTexts["Podcasts"].firstMatch.exists, "The selected library remains shared across destinations")
        capture("Native Library selected podcast")
    }
}
