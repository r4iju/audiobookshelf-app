import XCTest

/// Uses the presentation QA fixture on 25765 (`apple/scripts/verify-presentation.sh`), separate from the shared 1976x journeys.
@MainActor final class PresentationJourney: NativeJourney {
    nonisolated static let server = "http://127.0.0.1:25765/abs"
    static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    /// Nonisolated so teardown blocks can reset the fixture without waiting on the main actor.
    private nonisolated static func configure(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: Self.server + "/__fixture__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["mode": mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func open(_ menuItem: String, in app: XCUIApplication) {
        app.buttons["account"].tap()
        let item = app.buttons[menuItem]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(menuItem) is missing from the account menu")
        item.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Lists create rows only near the visible area, so scroll until the row exists and can be tapped.
    private func revealed(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let target = element(identifier, in: app)
        for _ in 0..<4 where !(target.exists && target.isHittable) { app.swipeUp() }
        return target
    }

    private func elapsedAtLeast(_ seconds: Int, in app: XCUIApplication) async {
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let elapsed = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return elapsed >= seconds
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [listened], timeout: Double(seconds) + 10)
    }

    // MARK: Language

    func testSavedLanguageTranslatesNativeScreensAndSurvivesRelaunch() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        open("Settings", in: app)
        let language = app.buttons["language-settings"]
        XCTAssertTrue(language.waitForExistence(timeout: 3))
        guard language.exists else { return }
        language.tap()
        XCTAssertEqual(app.buttons["language-system"].value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["language-coverage-note"].exists, "Partial translations must be disclosed")
        app.buttons["language-de"].tap()
        XCTAssertEqual(app.buttons["language-de"].value as? String, "Ausgewählt", "The selection state reads in the chosen language")
        XCTAssertTrue(app.navigationBars["Sprache"].waitForExistence(timeout: 3), "The open screen must switch without relaunch")
        let lastLegacyLanguage = app.buttons["language-zh-cn"]
        for _ in 0..<4 where !lastLegacyLanguage.exists { app.swipeUp() }
        XCTAssertTrue(lastLegacyLanguage.exists, "Every legacy language must remain selectable")
        app.navigationBars.buttons.firstMatch.tap()

        app.terminate(); app.launchArguments = Self.english; app.launch()
        XCTAssertTrue(app.buttons["account"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["account"].label, "Konto", "Icon-only controls must follow the chosen language, not the device")
        open("Einstellungen", in: app)
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 3), "The choice must survive relaunch")
        XCTAssertTrue(app.staticTexts["Haptische Rückmeldung"].exists)
        XCTAssertEqual(app.buttons["theme-light"].label, "Hell", "The theme keeps its legacy meaning")
        XCTAssertEqual(app.buttons["haptic-light"].label, "Leicht", "The haptic strength keeps its legacy meaning")
        capture("Native settings in German")
        app.buttons["language-settings"].tap()
        app.buttons["language-system"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 3), "System must return to the English device language")
    }

    func testDeviceLanguageAppliesUntilAnExplicitChoiceIsSaved() async throws {
        try await Self.configure("baseline")
        let french = ["-AppleLanguages", "(fr-FR)", "-AppleLocale", "fr_FR"]
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: french)
        let app = XCUIApplication()
        open("Paramètres", in: app)
        guard app.buttons["language-settings"].waitForExistence(timeout: 3) else { return XCTFail("Language settings are missing") }
        app.buttons["language-settings"].tap()
        XCTAssertEqual(app.buttons["language-system"].value as? String, "Sélectionné", "The selection state reads in the device language")
        app.buttons["language-en-us"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 3))
        app.terminate(); app.launchArguments = french; app.launch()
        XCTAssertTrue(app.buttons["account"].waitForExistence(timeout: 10))
        open("Settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3), "A saved choice must override the device language")
    }

    func testRightToLeftLanguageMirrorsNativeLayout() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        open("Settings", in: app)
        guard app.buttons["language-settings"].waitForExistence(timeout: 3) else { return XCTFail("Language settings are missing") }
        app.buttons["language-settings"].tap()
        let mark = app.images["language-selected-mark"]
        XCTAssertGreaterThan(mark.frame.midX, app.windows.firstMatch.frame.midX)
        app.buttons["language-ar"].tap()
        XCTAssertTrue(app.navigationBars["اللغة"].waitForExistence(timeout: 3))
        XCTAssertLessThan(mark.frame.midX, app.windows.firstMatch.frame.midX, "Arabic must mirror the row layout")
        capture("Native language settings in Arabic")
    }

    // MARK: Diagnostics

    func testDiagnosticsExplainAConnectionFailureWithoutExposingCredentials() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        func attempt(_ address: String) {
            open("Saved connections", in: app)
            app.buttons["Add server"].tap()
            let server = app.textFields["server"]
            XCTAssertTrue(server.waitForExistence(timeout: 5))
            server.tap(); server.typeText(address)
            app.textFields["username"].tap(); app.textFields["username"].typeText("qa")
            app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText("pw-secret-77")
            app.buttons["connect"].tap()
            XCTAssertTrue(app.staticTexts["connection-error"].firstMatch.waitForExistence(timeout: 20))
        }
        attempt("http://qa:hunter2-secret@127.0.0.1:25799/abs?token=leak-123")
        XCTAssertTrue(app.staticTexts["connection-error"].firstMatch.label.contains("without credentials"), "An address carrying credentials must be refused")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["account"].waitForExistence(timeout: 10))
        attempt("http://127.0.0.1:25799/abs")
        XCTAssertTrue(app.staticTexts["connection-error"].firstMatch.label.contains("could not be reached"), app.staticTexts["connection-error"].firstMatch.label)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["account"].waitForExistence(timeout: 10))

        open("Diagnostics", in: app)
        let event = element("diagnostic-event", in: app)
        XCTAssertTrue(event.waitForExistence(timeout: 5), "The failed connection must be recorded")
        guard event.exists else { return }
        XCTAssertTrue(event.label.contains("[server]"), "Addresses are masked by default: \(event.label)")
        let showAddress = app.switches["diagnostic-show-address"]
        showAddress.switches.firstMatch.tap()
        XCTAssertEqual(showAddress.value as? String, "1")
        XCTAssertTrue(element("diagnostic-event", in: app).label.contains("127.0.0.1:25799"), "The unreachable server must be identifiable for recovery")
        for secret in ["hunter2-secret", "leak-123", "pw-secret-77"] { XCTAssertFalse(app.debugDescription.contains(secret), secret) }
        capture("Native diagnostics")

        revealed("diagnostic-preview", in: app).tap()
        let report = app.staticTexts["diagnostic-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        XCTAssertTrue(report.label.contains("NSURLErrorDomain"), report.label)
        XCTAssertTrue(report.label.contains("127.0.0.1:25799"), report.label)
        for secret in ["hunter2-secret", "leak-123", "pw-secret-77"] { XCTAssertFalse(report.label.contains(secret), secret) }
        app.navigationBars.buttons.firstMatch.tap()

        revealed("diagnostic-share", in: app).tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "Export must use the user-initiated system share sheet")
        // On iPad the share sheet is a card whose Close button ignores a tap while it is still presenting.
        let closeShare = shareSheet.buttons["Close"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: closeShare)
        if shareSheet.exists, XCTWaiter().wait(for: [ready], timeout: 5) == .completed { closeShare.tap() }
        let shareClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: shareSheet)
        XCTAssertEqual(XCTWaiter().wait(for: [shareClosed], timeout: 5), .completed, "The share sheet must close")

        revealed("diagnostic-clear", in: app).tap()
        app.alerts.buttons["Clear"].tap()
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["No problems recorded"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("diagnostic-event", in: app).exists)
        app.terminate(); app.launchArguments = Self.english; app.launch()
        XCTAssertTrue(app.buttons["account"].waitForExistence(timeout: 10))
        open("Diagnostics", in: app)
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No problems recorded"].waitForExistence(timeout: 3), "Clearing must persist")
    }

    func testDiagnosticsRecordTheVisibleMediaFailure() async throws {
        try await Self.configure("broken-audio")
        addTeardownBlock { try await Self.configure("baseline") }
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap(); app.buttons["mini-player"].tap()
        let failure = app.staticTexts["playback-error"]
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        let message = failure.label
        app.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        open("Diagnostics", in: app)
        let event = element("diagnostic-event", in: app)
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(event.label.contains("Media"), event.label)
        XCTAssertTrue(event.label.contains(message), "\(event.label) should include \(message)")
        let playback = revealed("diagnostic-playback", in: app)
        XCTAssertTrue(playback.label.contains("Stories for Tomorrow"), playback.label)
    }

    func testDiagnosticsShowListeningWaitingToSync() async throws {
        try await Self.configure("offline-progress")
        addTeardownBlock { try await Self.configure("baseline") }
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap(); app.buttons["mini-player"].tap()
        await elapsedAtLeast(3, in: app)
        app.buttons["pause-playback"].tap()
        XCTAssertTrue(app.staticTexts["playback-error"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        open("Diagnostics", in: app)
        let event = element("diagnostic-event", in: app)
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertTrue(event.label.contains("Sync"), event.label)
        let pending = revealed("diagnostic-pending-listening", in: app)
        XCTAssertTrue(pending.label.contains("1: Stories for Tomorrow"), pending.label)
    }

    // MARK: Haptics

    private func observedHaptic(_ app: XCUIApplication) -> String { app.staticTexts["haptic-observation"].label }

    private func expectHaptic(_ action: String, _ strength: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts["haptic-observation"]
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", action + ":" + strength), object: probe)
        // Each probe query can take seconds on a loaded simulator, and the waiter polls between queries.
        XCTAssertEqual(XCTWaiter().wait(for: [observed], timeout: 10), .completed, "\(action) gave \(probe.exists ? probe.label : "no probe")", file: file, line: line)
    }

    func testChosenHapticStrengthCoversBaselineActions() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english + ["--observe-haptics"])
        let app = XCUIApplication()
        open("Settings", in: app)
        app.buttons["haptic-medium"].tap()
        expectHaptic("settings", "medium", in: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Show list"].tap()
        expectHaptic("layout", "medium", in: app)
        app.buttons["Sort library"].tap(); app.buttons["Title Z–A"].tap()
        expectHaptic("sort", "medium", in: app)
        app.buttons["Filter library"].tap(); app.buttons["All titles"].tap()
        expectHaptic("filter", "medium", in: app)
        // Title Z–A moved the first book to the end of the catalog; Continue listening still offers it.
        app.buttons["continue-book-0"].tap(); app.buttons["play-book"].tap()
        expectHaptic("play", "medium", in: app)
        app.buttons["mini-player"].tap()
        app.buttons["Chapters"].tap(); app.buttons["chapter-1"].tap()
        expectHaptic("chapter", "medium", in: app)
        app.buttons["Sleep timer"].tap(); app.buttons["5 minutes"].tap()
        expectHaptic("sleep-timer", "medium", in: app)
        app.buttons["Bookmarks"].tap()
        let title = app.textFields["bookmark-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Haptic passage")
        app.buttons["Save bookmark"].tap()
        expectHaptic("bookmark", "medium", in: app)
    }

    func testOffHapticsProduceNoFeedback() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english + ["--observe-haptics"])
        let app = XCUIApplication()
        open("Settings", in: app)
        app.buttons["haptic-heavy"].tap()
        expectHaptic("settings", "heavy", in: app)
        app.buttons["haptic-off"].tap()
        let before = observedHaptic(app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Show list"].tap()
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 5))
        XCTAssertEqual(observedHaptic(app), before, "Off must not produce feedback")
    }

    // MARK: Player display

    /// Book 0 has chapters Opening (0–8 s) and Next chapter (8–20 s). Leaves the player paused at 10 s.
    private func openPausedPlayerAtTenSeconds(_ app: XCUIApplication) {
        app.buttons["book-book-0"].tap(); app.buttons["play-book"].tap(); app.buttons["mini-player"].tap()
        let pause = app.buttons["pause-playback"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 5))
        app.buttons["Chapters"].tap(); app.buttons["chapter-0"].tap()
        expectLabel("playback-elapsed", "0 sec", in: app)
        app.buttons["Forward 10 seconds"].tap()
    }

    private func expectLabel(_ identifier: String, _ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = app.staticTexts[identifier]
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [matched], timeout: 5), .completed, "\(identifier) shows \(target.exists ? target.label : "nothing"), expected \(label)", file: file, line: line)
    }

    func testChapterTrackFollowsTheChapterWithTheTotalTrackAlongside() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        openPausedPlayerAtTenSeconds(app)
        playerSettings(app, [("chapter-track-setting", true), ("total-track-setting", true), ("scale-elapsed-setting", true)])
        expectLabel("playback-elapsed", "2 sec", in: app)
        expectLabel("playback-remaining", "−10 sec", in: app)
        expectLabel("total-elapsed", "10 sec", in: app)
        expectLabel("total-remaining", "−10 sec", in: app)
        capture("Native player with chapter and total tracks")

        playerSettings(app, [("total-track-setting", false)])
        XCTAssertFalse(app.staticTexts["total-elapsed"].exists, "Turning the total track off hides it")
        expectLabel("playback-elapsed", "2 sec", in: app)

        openPlayerSettings(app)
        app.switches["chapter-track-setting"].switches.firstMatch.tap()
        XCTAssertEqual(app.switches["total-track-setting"].value as? String, "1", "One track must stay visible")
        app.buttons["panel-done"].tap()
        app.swipeDown(); app.swipeDown()
        expectLabel("playback-elapsed", "10 sec", in: app)
        expectLabel("playback-remaining", "−10 sec", in: app)
        XCTAssertFalse(app.staticTexts["total-elapsed"].exists, "The single track already shows the whole book")
    }

    func testElapsedTimeScalesWithPlaybackSpeedUntilTurnedOff() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        openPausedPlayerAtTenSeconds(app)
        playerSettings(app, [("chapter-track-setting", false), ("scale-elapsed-setting", true)])
        app.buttons["Playback speed"].tap(); app.buttons["speed-2"].tap()
        expectLabel("playback-elapsed", "5 sec", in: app)
        expectLabel("playback-remaining", "−5 sec", in: app)
        playerSettings(app, [("scale-elapsed-setting", false)])
        expectLabel("playback-elapsed", "10 sec", in: app)
        expectLabel("playback-remaining", "−5 sec", in: app)
    }

    func testLockedPlayerPreventsAccidentalSeekingUntilUnlocked() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english)
        let app = XCUIApplication()
        openPausedPlayerAtTenSeconds(app)
        playerSettings(app, [("lock-player", true)])
        let unlock = app.buttons["unlock-player"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3), "A locked player must offer Unlock")
        func expectLocked(_ locked: Bool, file: StaticString = #filePath, line: UInt = #line) {
            for control in ["Back 10 seconds", "Forward 10 seconds", "Chapters", "Bookmarks", "Close playback"] {
                let button = app.buttons[control]
                for _ in 0..<3 where !button.exists { app.swipeUp() }
                XCTAssertEqual(button.isEnabled, !locked, control, file: file, line: line)
            }
            app.swipeDown(); app.swipeDown()
            XCTAssertEqual(app.sliders["playback-position"].isEnabled, !locked, "Scrubbing", file: file, line: line)
        }
        expectLocked(true)
        XCTAssertTrue(app.buttons["resume-playback"].isEnabled, "Play and pause stay available")
        capture("Native player locked")

        app.buttons["Done"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 3), "The lock is kept")
        expectLocked(true)
        unlock.tap()
        XCTAssertFalse(unlock.waitForExistence(timeout: 1))
        expectLocked(false)
    }

    // MARK: Large text

    func testAccessibilityTextSizeKeepsPlayerControlsOnScreen() async throws {
        try await Self.configure("baseline")
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: Self.english + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.swipeUp()
        app.buttons["play-book"].tap(); app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["Back 10 seconds"].waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        for control in ["Back 10 seconds", "Forward 10 seconds", "Chapters", "Playback speed", "Bookmarks", "Sleep timer"] {
            let button = app.buttons[control]
            for _ in 0..<3 where !(button.exists && button.isHittable) { app.swipeUp() }
            XCTAssertTrue(button.frame.minX >= window.minX && button.frame.maxX <= window.maxX, "\(control) is clipped at \(button.frame) in \(window)")
        }
        // A labelled control squeezed into a narrow column breaks its word over several lines and grows taller than wide.
        for control in ["Chapters", "Bookmarks", "Sleep timer"] {
            let frame = app.buttons[control].frame
            XCTAssertLessThan(frame.height, frame.width, "\(control) breaks its label across lines at \(frame)")
        }
        capture("Native player with accessibility text size")
    }
}
