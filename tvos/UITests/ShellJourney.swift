import XCTest

/// Many server libraries belong to a contextual chooser, without crowding out TV destinations.
final class ShellJourney: TVJourney {
    func testManyLibrariesKeepTheShellBoundedAndRemainSelectable() async throws {
        try await Fixture.configure("many-libraries")
        signIn()
        waitForHome()
        capture("many-libraries-shell")
        XCTAssertEqual(app.tabBars.buttons.count, 4, "Twelve libraries must not create twelve root tabs")
        for destination in ["Listen Now", "Library", "Search", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[destination].exists)
        }
        tab("Library")
        select(app.buttons["library-chooser"])
        focus(app.cells.containing(.button, identifier: "library-choice-books").firstMatch)
        capture("library-chooser")
        for id in ["books", "podcasts"] + (1...10).map({ "archive-\($0)" }) {
            XCTAssertTrue(app.buttons["library-choice-\(id)"].exists, "Every configured library remains available")
        }
        let lastLibrary = app.cells.containing(.button, identifier: "library-choice-archive-10").firstMatch
        focus(lastLibrary)
        capture("library-chooser-end")
        select(lastLibrary)
        wait(app.buttons["library-chooser"], label: "Archive 10")
        let title = app.buttons["item-book-60"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        capture("library-unfocused")
        focus(title)
        capture("library-focused")
        select(title)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "Stories for Tomorrow 61")
        capture("archive-detail")
        remote.press(.menu)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(title), "Back restores focus to the chosen library's title")
        capture("library-back-focused")
        tab("Settings")
        tab("Library")
        XCTAssertEqual(app.buttons["library-chooser"].label, "Archive 10", "Destination changes keep the chosen library")
        select(app.buttons["library-chooser"])
        select(app.cells.containing(.button, identifier: "library-choice-podcasts").firstMatch)
        XCTAssertTrue(app.buttons["item-podcast"].waitForExistence(timeout: 15))
        tab("Search")
        search("Tomorrow 61")
        XCTAssertTrue(app.buttons["search.book-60"].waitForExistence(timeout: 15))
        capture("multi-library-search")
        let requests = try await observations().requests
        for id in ["books", "podcasts"] + (1...10).map({ "archive-\($0)" }) {
            XCTAssertTrue(requests.contains { $0.path == "/api/libraries/\(id)/search" }, "Search retains all-library scope")
        }
    }
}
