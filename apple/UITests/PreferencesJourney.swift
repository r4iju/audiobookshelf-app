import XCTest

@MainActor final class PreferencesJourney: NativeJourney {
    func testLegacyImportOpensBeforeSigningIntoAServer() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        XCTAssertTrue(app.textFields["server"].waitForExistence(timeout: 8))
        app.swipeUp()
        let migration = app.buttons["Import previous app data"]
        XCTAssertTrue(migration.waitForExistence(timeout: 3))
        guard migration.exists else { return }
        migration.tap()
        XCTAssertTrue(app.buttons["Choose export"].waitForExistence(timeout: 3))
    }

    func testLegacyImportExplainsExportAndReauthentication() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Settings"].tap(); app.swipeUp()
        let migration = app.buttons["Import previous app data"]
        XCTAssertTrue(migration.waitForExistence(timeout: 3))
        guard migration.exists else { return }
        migration.tap()
        XCTAssertTrue(app.buttons["Choose export"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sign in again after importing to access each account."].exists)
        XCTAssertTrue(app.staticTexts["Your previous app and its original files stay available."].exists)
        capture("Native legacy import")
    }

    func testSeparateStreamingAndDownloadNetworkChoicesPersist() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Settings"].tap()
        app.swipeUp()
        let network = app.buttons["Network preferences"]
        XCTAssertTrue(network.waitForExistence(timeout: 3))
        guard network.exists else { return }
        network.tap()
        app.buttons["streaming-ask"].tap(); app.buttons["downloads-never"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["account"].tap(); app.buttons["Settings"].tap(); app.swipeUp()
        app.buttons["Network preferences"].tap()
        XCTAssertEqual(app.buttons["streaming-ask"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["downloads-never"].value as? String, "Selected")
        app.buttons["streaming-never"].tap(); app.buttons["downloads-always"].tap()
        app.terminate(); app.launch()
        app.buttons["account"].tap(); app.buttons["Settings"].tap(); app.swipeUp()
        app.buttons["Network preferences"].tap()
        XCTAssertEqual(app.buttons["streaming-never"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["downloads-always"].value as? String, "Selected")
        capture("Native network preferences")
    }
    func testYearReviewUsesServerCalendarWithBuddhistDeviceLocale() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false, arguments: ["-AppleLocale", "en_US@calendar=buddhist"])
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Statistics"].tap(); app.buttons["Year in review"].tap()
        XCTAssertTrue(app.staticTexts["120 minutes listened"].waitForExistence(timeout: 8))
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/me/stats/year/\(year)" }, "Protocol years must remain Gregorian with another device calendar")
    }
    func testYearReviewShowsServerTotalsAndChangesYear() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Statistics"].tap()
        let review = app.buttons["Year in review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        guard review.exists else { return }
        review.tap()
        XCTAssertTrue(app.staticTexts["120 minutes listened"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["5 books finished"].exists)
        XCTAssertTrue(app.staticTexts["9 books listened to"].exists)
        XCTAssertTrue(app.staticTexts["12 listening sessions"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Mira Vale"].exists)
        XCTAssertTrue(app.staticTexts["QA Narrator"].exists)
        capture("Native year in review")
        app.swipeDown(); app.buttons["Previous year"].tap()
        XCTAssertTrue(app.staticTexts["60 minutes listened"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["2 books finished"].exists)
        let year = Calendar.current.component(.year, from: Date())
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.path == "/api/me/stats/year/\(year)" })
        XCTAssertTrue(requests.contains { $0.path == "/api/me/stats/year/\(year - 1)" })
    }
    func testLiveBookProgressRequiresCompletionConfirmationWithoutLeavingDetails() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-1"].tap(); app.buttons["play-book"].tap()
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
            guard let button = element as? XCUIElement else { return false }
            return button.staticTexts.allElementsBoundByIndex.contains { label in
                label.label.contains(" of ") && (Int(label.label.split(separator: " ").first ?? "") ?? 0) > 0
            }
        }, object: app.buttons["mini-player"])
        await fulfillment(of: [elapsed], timeout: 8)
        app.buttons["Mark finished"].tap()
        XCTAssertTrue(app.alerts["Mark book finished?"].waitForExistence(timeout: 3), "Live progress must not bypass the saved-progress confirmation")
        if app.alerts["Mark book finished?"].exists { app.alerts["Mark book finished?"].buttons["Cancel"].tap() }
        XCTAssertTrue(app.buttons["mini-pause-playback"].exists, "Canceling completion must preserve listening")
    }
    func testFinishedBookLeavesNotFinishedFilterWhenReturningToCatalog() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["Filter library"].tap(); app.buttons["Progress"].tap(); app.buttons["Not finished"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 8))
        app.buttons["book-book-0"].tap(); app.buttons["Mark finished"].tap()
        app.alerts["Mark book finished?"].buttons["Mark finished"].tap()
        XCTAssertTrue(app.buttons["Mark unfinished"].waitForExistence(timeout: 8))
        app.navigationBars.buttons["BackButton"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["book-book-0"])
        await fulfillment(of: [removed], timeout: 8)
        XCTAssertTrue(app.staticTexts["60"].exists, "The filtered total must reflect completion")
    }
    func testBookCompletionAfterListeningSurvivesRelaunchAndCanBeReversed() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap(); app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 8))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        app.navigationBars.buttons["Done"].tap()
        let finish = app.buttons["Mark finished"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        guard finish.exists else { return }
        finish.tap()
        XCTAssertTrue(app.alerts["Mark book finished?"].waitForExistence(timeout: 3))
        app.alerts["Mark book finished?"].buttons["Mark finished"].tap()
        XCTAssertTrue(app.buttons["Mark unfinished"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["mini-pause-playback"].exists, "Close matching listening before explicit completion")
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["Mark unfinished"].waitForExistence(timeout: 8))
        app.buttons["Mark unfinished"].tap()
        XCTAssertTrue(app.buttons["Mark finished"].waitForExistence(timeout: 8))
        let requests = try await fixtureRequests()
        XCTAssertEqual(requests.filter { $0.method == "PATCH" && $0.path == "/api/me/progress/book-0" }.count, 2)
        app.terminate(); app.launch(); app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["Mark finished"].waitForExistence(timeout: 8))
    }
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
        app.swipeUp()
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
        app.buttons["account"].tap(); accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.buttons["Show covers"].waitForExistence(timeout: 10), "The device display preference must also apply to another library")
        app.buttons["Show covers"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Show list"].waitForExistence(timeout: 10))
    }
}
