import XCTest

@MainActor final class SavedConnectionsJourney: NativeJourney {
    func testAccountsOnTheSameServerKeepTheirOwnListeningPosition() async throws {
        try await FixtureControl.configure("baseline")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 10
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [listened], timeout: 15)
        app.buttons["pause-playback"].tap()
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["account"].tap()
        app.buttons["Saved connections"].tap()
        app.buttons["Add server"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:19765/abs")
        app.textFields["username"].tap()
        app.textFields["username"].typeText("qa-other")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 10))
        app.buttons["library-books"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        app.buttons["mini-pause-playback"].tap()
        app.buttons["mini-player"].tap()
        let otherPosition = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 2 && seconds < 5
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [otherPosition], timeout: 10)
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["account"].tap()
        app.buttons["Saved connections"].tap()
        app.buttons["qa on http://127.0.0.1:19765/abs"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        app.buttons["mini-pause-playback"].tap()
        app.buttons["mini-player"].tap()
        let restoredPosition = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 10 && seconds < 14
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [restoredPosition], timeout: 10)
        let reports = try await fixtureObservations().reports
        XCTAssertTrue(reports.contains { $0.userId == "00000000-0000-4000-8000-000000000001" && $0.currentTime >= 10 && $0.timeListened > 0 })
        XCTAssertFalse(reports.contains { $0.userId == "00000000-0000-4000-8000-000000000002" && $0.currentTime >= 10 })
    }

    func testSavedServersKeepLibraryChoicesAndRecoverUnsentListeningWhenSwitchedBack() async throws {
        try await FixtureControl.configure("offline-progress")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 10
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [listened], timeout: 15)
        app.buttons["pause-playback"].tap()
        app.buttons["Done"].tap()
        app.navigationBars.buttons["Audiobooks"].tap()
        app.buttons["account"].tap()
        let connections = app.buttons["Saved connections"]
        XCTAssertTrue(connections.waitForExistence(timeout: 3))
        guard connections.exists else { return }
        connections.tap()
        app.buttons["Add server"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:19766/abs")
        app.textFields["username"].tap()
        app.textFields["username"].typeText("qa")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-podcasts"].waitForExistence(timeout: 10))
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.staticTexts["Podcasts"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["book-podcast"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mini-player"].exists)
        try await FixtureControl.configure("baseline")
        app.buttons["account"].tap()
        app.buttons["Saved connections"].tap()
        app.buttons["connection-http://127.0.0.1:19765/abs"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        let reports = try await fixtureObservations().reports
        XCTAssertTrue(reports.contains { $0.path == "/api/session/local-all" && $0.currentTime >= 10 && $0.timeListened > 0 })
        app.buttons["account"].tap()
        app.buttons["Saved connections"].tap()
        app.buttons["connection-http://127.0.0.1:19766/abs"].tap()
        XCTAssertTrue(app.staticTexts["Podcasts"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Podcasts"].firstMatch.waitForExistence(timeout: 10))
    }
}
