import XCTest

/// Diagnostics, language and accessibility on the TV, operated only with the remote.
final class ReadinessJourney: TVJourney {
    /// Nothing listens here, so connecting fails the way an unreachable server does.
    static let unreachable = "http://127.0.0.1:\(port("ABS_TV_HTTP_PORT", 20765) + 34)/abs"

    func testFailedSignInIsDiagnosedWithoutCredentials() {
        launch(reset: true)
        let server = app.textFields["serverURL"]
        enter("http://qa:synthetic-secret@127.0.0.1:1/abs?token=synthetic-token", into: server)
        enter("qa", into: app.textFields["username"])
        enter("qa", into: app.secureTextFields["password"])
        select(app.buttons["connect"])
        XCTAssertTrue(app.staticTexts["sign-in-error"].waitForExistence(timeout: 10))
        // Events are kept across launches; the second attempt starts from an empty form.
        app.terminate()
        launch(reset: false)
        enter(Self.unreachable, into: server)
        enter("qa", into: app.textFields["username"])
        enter("qa", into: app.secureTextFields["password"])
        select(app.buttons["connect"])
        wait(app.staticTexts["sign-in-error"], label: "The server could not be reached. Check that it is running and that the TV is on the network, then try again.")

        let diagnostics = app.buttons["sign-in-diagnostics"]
        select(diagnostics)
        let events = app.descendants(matching: .any).matching(identifier: "diagnostic-event")
        XCTAssertTrue(events.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(events.count, 2, "Both failed attempts, and nothing from earlier runs")
        let newest = events.element(boundBy: 0).label
        XCTAssertTrue(newest.contains("could not be reached"), newest)
        XCTAssertTrue(newest.contains("http://[server]/abs"), "Addresses are masked until shown: \(newest)")
        XCTAssertTrue(events.element(boundBy: 1).label.contains("without credentials"), events.element(boundBy: 1).label)
        for secret in ["synthetic-secret", "synthetic-token"] {
            XCTAssertFalse(app.debugDescription.contains(secret), "\(secret) must not be shown")
        }
        audit("diagnostics")

        select(element("diagnostic-show-address"))
        let shown = Self.unreachable
        let revealed = NSPredicate(format: "label CONTAINS %@", shown)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: revealed, evaluatedWith: events.element(boundBy: 0))], timeout: 5), .completed, events.element(boundBy: 0).label)
        XCTAssertTrue(events.element(boundBy: 1).label.contains("http://127.0.0.1:1/abs?token=[redacted]"), events.element(boundBy: 1).label)
        XCTAssertFalse(app.debugDescription.contains("synthetic-secret"))
        capture("diagnostics-sign-in")

        remote.press(.menu)
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        waitForFocus(diagnostics, "Back returns to the Diagnostics button")
    }

    func testCatalogFailureIsRecordedAndClearedFromSettings() async throws {
        try await Fixture.configure("offline-library")
        signIn()
        let retry = app.buttons["retry-catalog"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20), app.debugDescription)
        try await Fixture.configure("baseline")
        select(retry)
        waitForHome()

        tab("Settings")
        let entry = app.buttons["diagnostics-setting"]
        select(entry)
        let events = app.descendants(matching: .any).matching(identifier: "diagnostic-event")
        XCTAssertTrue(events.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(events.firstMatch.label.contains("The server returned HTTP 503"), events.firstMatch.label)
        let server = element("diagnostic-server")
        XCTAssertTrue(server.exists)
        XCTAssertTrue(server.label.contains("http://[server]/abs"), server.label)
        XCTAssertTrue(element("diagnostic-account").label.contains("qa"), "Signed-in state helps recovery")
        XCTAssertTrue(element("diagnostic-pending-listening").exists)

        select(app.buttons["diagnostic-clear"])
        let confirm = app.alerts.buttons["Clear"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        select(confirm)
        XCTAssertTrue(element("diagnostic-empty").waitForExistence(timeout: 5))
        XCTAssertEqual(events.count, 0)

        remote.press(.menu)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        waitForFocus(entry, "Back returns to Diagnostics in Settings")
    }

    func testGermanLocalizesTheInterfaceAndPersists() {
        signIn()
        waitForHome()
        tab("Settings")
        let language = app.buttons["language-setting"]
        select(language)
        let german = app.buttons["language-de"]
        select(german)
        XCTAssertTrue(app.tabBars.buttons["Startseite"].waitForExistence(timeout: 5), app.tabBars.firstMatch.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["Suchen"].exists)
        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].exists)
        XCTAssertEqual(german.value as? String, "Ausgewählt")
        XCTAssertTrue(element("language-note").exists, "Partial translation is disclosed")
        audit("language")
        remote.press(.menu)
        waitForFocus(language, "Back returns to Language")
        XCTAssertTrue(app.staticTexts["Konto"].exists, "Settings sections follow the language")
        capture("settings-german")

        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.tabBars.buttons["Startseite"].waitForExistence(timeout: 20), "The choice survives relaunch")
        let shelf = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Weiterhören")).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 10), "Home shelves use the legacy translation: \(app.staticTexts.debugDescription.prefix(2000))")
        select(app.buttons["continue-listening.book-0"])
        let finish = app.buttons["mark-finished"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        XCTAssertEqual(finish.label, "Als beendet markieren", "Details use the legacy translation")

        remote.press(.menu)
        tab("Einstellungen")
        select(app.buttons["language-setting"])
        select(app.buttons["language-system"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5), "System default follows the English simulator")
    }

    func testArabicMirrorsTheInterface() {
        signIn()
        waitForHome()
        tab("Settings")
        select(app.buttons["language-setting"])
        select(app.buttons["language-ar"])
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].waitForExistence(timeout: 5), app.tabBars.firstMatch.debugDescription)
        remote.press(.menu)
        let account = app.staticTexts["الحساب"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(account.frame.midX, app.windows.firstMatch.frame.midX, "Section titles start on the right in Arabic")
        capture("settings-arabic")
    }

    func testMainScreensPassTheAccessibilityAudit() {
        launch(reset: true)
        XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 10))
        audit("sign-in")
        signIn(reset: false)
        waitForHome()
        audit("home")
        select(app.buttons["continue-listening.book-0"])
        XCTAssertTrue(app.buttons["play-item"].waitForExistence(timeout: 10))
        audit("details")
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let total = element("total-progress")
        XCTAssertTrue(total.exists, "The book's progress is identified")
        XCTAssertEqual(total.label, "Book progress")
        XCTAssertEqual(element("chapter-progress").label, "Chapter progress")
        XCTAssertTrue((total.value as? String ?? "").contains("remaining"), "Progress is read as time, not a bare percentage: \(String(describing: total.value))")
        audit("now-playing")
        tab("Settings")
        audit("settings")
        tab("Search")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element("total-progress"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Now Playing has left the screen")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        capture("search-prompt")
        // The system search field reports its prompt as clipped although it is shown in full (tvos/evidence/readiness-search-prompt.png).
        audit("search", ignoring: .textClipped)
    }

    /// Focus can settle a moment after Back while the screen behind is restored.
    func waitForFocus(_ element: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let focused = expectation(for: NSPredicate { _, _ in self.hasFocus(element) }, evaluatedWith: element)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "\(message); focused \(self.focused.debugDescription)", file: file, line: line)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Runs Xcode's accessibility audit on the current screen and reports every issue at once.
    func audit(_ screen: String, ignoring ignored: XCUIAccessibilityAuditType = [], file: StaticString = #filePath, line: UInt = #line) {
        var issues: [String] = []
        do {
            // Hit regions matter for touch; tvOS moves focus between controls and only flagged non-interactive progress bars.
            try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting([.hitRegion]).subtracting(ignored)) { issue in
                issues.append("\(issue.auditType): \(issue.compactDescription) | \(issue.element?.debugDescription.prefix(160) ?? "no element")")
                return true
            }
        } catch {
            XCTFail("Audit on \(screen) failed to run: \(error)", file: file, line: line)
        }
        XCTAssertTrue(issues.isEmpty, "Accessibility audit on \(screen):\n" + issues.joined(separator: "\n"), file: file, line: line)
    }
}
