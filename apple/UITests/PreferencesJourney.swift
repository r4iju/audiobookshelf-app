import XCTest

@MainActor final class PreferencesJourney: NativeJourney {
    func testThemeAndHapticPreferencesPersistAndRemainAvailableAfterRelaunch() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        guard settings.exists else { return }
        settings.tap()
        XCTAssertTrue(app.buttons["theme-black"].waitForExistence(timeout: 5))
        app.buttons["theme-black"].tap()
        app.buttons["haptic-off"].tap()
        XCTAssertEqual(app.buttons["theme-black"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["haptic-off"].value as? String, "Selected")
        capture("Native black appearance settings")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["account"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["theme-black"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["theme-black"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["haptic-off"].value as? String, "Selected")
        app.buttons["theme-light"].tap(); app.buttons["haptic-heavy"].tap()
        capture("Native light appearance settings")
        app.terminate(); app.launch()
        app.buttons["account"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["theme-light"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["theme-light"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["haptic-heavy"].value as? String, "Selected")
    }
    func testStatisticsShowServerListeningTotalsAndRecentSessions() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap()
        let stats = app.buttons["Statistics"]
        XCTAssertTrue(stats.waitForExistence(timeout: 3))
        guard stats.exists else { return }
        stats.tap()
        XCTAssertTrue(app.staticTexts["61 minutes listened"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3 days listened"].exists)
        XCTAssertTrue(app.staticTexts["0 titles finished"].exists)
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 03"].exists)
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/me/listening-stats" })
        capture("Native listening statistics")
    }
    func testChosenCatalogLayoutSurvivesRelaunchAndLibrarySwitch() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["Show list"].waitForExistence(timeout: 5))
        app.buttons["Show list"].tap()
        XCTAssertTrue(app.buttons["Show covers"].exists)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["Show covers"].waitForExistence(timeout: 10), "The chosen list presentation must survive relaunch")
        guard app.buttons["Show covers"].exists else { return }
        app.buttons["account"].tap(); app.buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.buttons["Show covers"].waitForExistence(timeout: 10), "The device display preference must also apply to another library")
        app.buttons["Show covers"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Show list"].waitForExistence(timeout: 10))
    }
}
