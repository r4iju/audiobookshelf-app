import XCTest

final class LayoutStabilityJourney: TVJourney {
    func testPlaybackUpdatesDoNotMoveTheHomeShelf() {
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        tab("Listen Now")
        if app.staticTexts["detail-title"].exists { remote.press(.menu) }
        let tile = app.buttons["continue-listening.book-0"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        sleep(1)
        let initial = tile.frame.minY
        var positions: [CGFloat] = []
        for _ in 0..<50 {
            positions.append(tile.frame.minY)
            Thread.sleep(forTimeInterval: 0.04)
        }
        let excursion = positions.map { abs($0 - initial) }.max() ?? 0
        print("TV_LAYOUT_STABILITY initial=\(initial) min=\(positions.min() ?? initial) max=\(positions.max() ?? initial)")
        XCTAssertLessThanOrEqual(excursion, 1, "Playback updates must not displace a stationary home shelf")
    }
}

extension LayoutStabilityJourney {
    func testSuccessfulProgressSaveDoesNotMovePlaybackControls() async throws {
        try await Fixture.configure("long-audio")
        var request = URLRequest(url: URL(string: TVJourney.fixture + "/__related__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"syncDelay":2}"#.utf8)
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let warning = app.staticTexts["now-playing-saves-waiting"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: warning)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        _ = try await URLSession.shared.data(for: request)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
        let title = app.staticTexts["now-playing-title"]
        let initial = title.frame.minY
        remote.press(.playPause)
        var positions: [CGFloat] = []
        for _ in 0..<50 {
            positions.append(title.frame.minY)
            Thread.sleep(forTimeInterval: 0.04)
        }
        let excursion = positions.map { abs($0 - initial) }.max() ?? 0
        print("TV_SAVE_LAYOUT initial=\(initial) min=\(positions.min() ?? initial) max=\(positions.max() ?? initial)")
        XCTAssertLessThanOrEqual(excursion, 1, "A successful in-flight progress save must not move the playback title")
        XCTAssertFalse(app.staticTexts["now-playing-saves-waiting"].exists, "A successful save is not an unanswered earlier save")
    }
}

// A real unknown outcome must remain actionable without recentering the hero.
extension LayoutStabilityJourney {
    func testUnansweredSaveDoesNotMovePlaybackControls() async throws {
        try await Fixture.configure("long-audio")
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await Fixture.configure("held-sync")
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
        let initial = app.staticTexts["now-playing-title"].frame.minY
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["now-playing-saves-waiting"].waitForExistence(timeout: 10))
        let final = app.staticTexts["now-playing-title"].frame.minY
        print("TV_UNKNOWN_SAVE_LAYOUT initial=\(initial) final=\(final)")
        XCTAssertEqual(final, initial, accuracy: 1, "Recovery rows must not recenter the playback hero")
    }
}
