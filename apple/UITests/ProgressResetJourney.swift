import XCTest

/// Discarding progress from book and episode details, against apple/scripts/progress_reset_fixture.py on 27765,
/// which apple/scripts/verify-progress-reset.sh starts. The fixture seeds book-0, book-1 and both podcast episodes at 6 seconds.
@MainActor final class ProgressResetJourney: NativeJourney {
    static let fixture = "http://127.0.0.1:27765/abs"
    static let missingAction = "No discard-progress action in these details: the progress reset UI (docs/modernization/APPLE-PROGRESS-RESET-UI.patch) is not in this build."

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ABS_PROGRESS_RESET_QA"] == "1", "Run apple/scripts/verify-progress-reset.sh, which starts the progress reset fixture on 27765.")
    }

    private func openBook(_ id: String, fail: String? = nil) async throws -> XCUIApplication {
        try await ResetFixture.configure(fail: fail)
        connectSelectAndRestore(serverURL: Self.fixture, verifyRestoration: false)
        let app = XCUIApplication()
        let book = app.buttons["book-" + id]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 10))
        return app
    }

    private func listened(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "listened ·")).firstMatch
    }

    /// Fails first, and stops the test, when the details have no discard action, after the details show the seeded progress.
    private func discardAction(in app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(listened(in: app).waitForExistence(timeout: 10), "The details did not show the seeded progress. " + app.debugDescription)
        let discard = app.buttons["discard-progress"]
        if !(discard.waitForExistence(timeout: 5) && discard.isHittable) {
            for _ in 0..<4 where !(discard.exists && discard.isHittable) { app.swipeUp() }
        }
        return try XCTUnwrap(discard.exists ? discard : nil, Self.missingAction + " " + app.debugDescription)
    }

    private func confirmation(in app: XCUIApplication) -> XCUIElement {
        let alert = app.alerts["Confirm"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Discarding asks for confirmation. " + app.debugDescription)
        XCTAssertTrue(alert.staticTexts["Are you sure you want to reset your progress?"].exists)
        return alert
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) async {
        await fulfillment(of: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)], timeout: timeout)
    }

    func testCancellingTheConfirmationKeepsProgressAndSendsNoDelete() async throws {
        let app = try await openBook("book-0")
        try discardAction(in: app).tap()
        confirmation(in: app).buttons["Cancel"].tap()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let observed = try await ResetFixture.observations()
        XCTAssertFalse(observed.requests.contains { $0.method == "DELETE" }, "Cancel must not delete progress")
        XCTAssertTrue(observed.progress.contains { $0.libraryItemId == "book-0" && $0.episodeId == nil })
        XCTAssertTrue(listened(in: app).exists)
        XCTAssertTrue(app.buttons["play-book"].label.contains("Resume listening"))
        XCTAssertTrue(app.buttons["discard-progress"].exists)
    }

    func testAConfirmedBookResetRemovesItsProgressAndPlaysFromTheStart() async throws {
        let app = try await openBook("book-0")
        try discardAction(in: app).tap()
        confirmation(in: app).buttons["Discard progress"].tap()
        await waitUntilGone(listened(in: app))
        XCTAssertFalse(app.buttons["discard-progress"].exists, "Without progress there is nothing to discard")
        capture("progress-reset-book")
        var observed = try await ResetFixture.observations()
        XCTAssertEqual(observed.deleted.map(\.libraryItemId), ["book-0"])
        XCTAssertEqual(Set(observed.progress.map(\.key)), [ResetFixture.Key("book-1", nil), ResetFixture.Key("podcast", "episode"), ResetFixture.Key("podcast", "episode-morning")])

        let play = app.buttons["play-book"]
        XCTAssertTrue(play.label.contains("Start listening"), play.label)
        play.tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        observed = try await ResetFixture.observations()
        XCTAssertEqual(observed.sessions.last?.libraryItemId, "book-0")
        XCTAssertEqual(observed.sessions.last?.currentTime, 0, "The server starts a session without progress at 0")
        app.buttons["mini-player"].tap()
        let elapsed = app.staticTexts["playback-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        let seconds = try XCTUnwrap(Int(elapsed.label.split(separator: " ").first ?? ""), elapsed.label)
        XCTAssertLessThan(seconds, 6, "Playback resumes from the start, not from the discarded 6 seconds")
        app.buttons["pause-playback"].tap()
        app.buttons["Done"].tap()

        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["continue-book-1"].waitForExistence(timeout: 10), "Other progress stays in Continue listening")
        XCTAssertFalse(app.buttons["continue-book-0"].exists, "The reset book leaves Continue listening")
    }

    func testAConfirmedEpisodeResetRemovesOnlyThatEpisodesProgress() async throws {
        try await ResetFixture.configure(fail: nil)
        connectSelectAndRestore(serverURL: Self.fixture, verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Change library"].tap(); app.buttons["library-podcasts"].tap()
        XCTAssertTrue(app.buttons["book-podcast"].waitForExistence(timeout: 10))
        app.buttons["book-podcast"].tap()
        let evening = app.buttons["episode-episode"]
        XCTAssertTrue(evening.waitForExistence(timeout: 10))
        evening.tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 10))
        try discardAction(in: app).tap()
        confirmation(in: app).buttons["Discard progress"].tap()
        await waitUntilGone(listened(in: app))
        capture("progress-reset-episode")
        let observed = try await ResetFixture.observations()
        XCTAssertEqual(observed.deleted.map(\.key), [ResetFixture.Key("podcast", "episode")])
        XCTAssertEqual(Set(observed.progress.map(\.key)), [ResetFixture.Key("book-0", nil), ResetFixture.Key("book-1", nil), ResetFixture.Key("podcast", "episode-morning")])
        XCTAssertTrue(app.buttons["play-book"].label.contains("Start episode"), app.buttons["play-book"].label)

        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        let morning = app.buttons["episode-episode-morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 10))
        morning.tap()
        XCTAssertTrue(listened(in: app).waitForExistence(timeout: 10), "The other episode keeps its progress")
        XCTAssertTrue(app.buttons["discard-progress"].exists)
    }

    func testAFailedResetIsReportedAndDiscardingAgainSucceeds() async throws {
        let app = try await openBook("book-0", fail: "delete")
        try discardAction(in: app).tap()
        confirmation(in: app).buttons["Discard progress"].tap()
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Discarding progress has not finished")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10), "The failed reset is reported. " + app.debugDescription)
        XCTAssertTrue(listened(in: app).exists, "Progress is kept when the server did not delete it")
        XCTAssertTrue(app.buttons["play-book"].label.contains("Resume listening"))
        capture("progress-reset-failure")
        var observed = try await ResetFixture.observations()
        XCTAssertTrue(observed.deleted.isEmpty)
        XCTAssertTrue(observed.progress.contains { $0.key == ResetFixture.Key("book-0", nil) })

        try discardAction(in: app).tap()
        confirmation(in: app).buttons["Discard progress"].tap()
        await waitUntilGone(listened(in: app))
        XCTAssertFalse(failure.exists)
        observed = try await ResetFixture.observations()
        XCTAssertEqual(observed.requests.filter { $0.method == "DELETE" }.count, 2)
        XCTAssertEqual(observed.deleted.map(\.libraryItemId), ["book-0"])
    }
}

enum ResetFixture {
    struct Key: Hashable {
        let item: String; let episode: String?
        init(_ item: String, _ episode: String?) { self.item = item; self.episode = episode }
    }
    struct Request: Decodable { let method: String; let path: String }
    struct Row: Decodable {
        let libraryItemId: String; let episodeId: String?
        var key: Key { Key(libraryItemId, episodeId) }
    }
    struct Session: Decodable { let libraryItemId: String; let episodeId: String?; let currentTime: Double }
    struct Observed: Decodable { let requests: [Request]; let deleted: [Row]; let progress: [Row]; let sessions: [Session] }

    static func configure(fail: String?) async throws {
        var request = URLRequest(url: URL(string: ProgressResetJourney.fixture + "/__reset__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fail.map { ["fail": $0] } ?? [:])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    static func observations() async throws -> Observed {
        let (data, _) = try await URLSession.shared.data(from: URL(string: ProgressResetJourney.fixture + "/__reset__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data)
    }
}
