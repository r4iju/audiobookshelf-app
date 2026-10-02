import XCTest

/// QA probe, not part of the suite: the production TV app, driven only by the remote, against the isolated
/// Audiobookshelf 2.30.0 container `abs-apple-qa` (19890). Runs after the phone probe, so the same synthetic account
/// already has progress saved by another client. Results are read from the server's own API.
@MainActor final class RealServerProbe: TVJourney {
    /// Seeded ids differ per server; `common.sh` resolves them by title and passes them as `TEST_RUNNER_ABS_RS_*`.
    private static let env = ProcessInfo.processInfo.environment
    static let server = env["ABS_RS_SERVER"] ?? "http://127.0.0.1:19890"
    static let longTide = env["ABS_RS_LONG_TIDE"] ?? ""
    static let eveningStories = env["ABS_RS_EVENING_STORIES"] ?? ""

    /// The real server has no fixture modes to reset.
    override func setUp() async throws { continueAfterFailure = false }

    private func get(_ path: String) async throws -> (Int, [String: Any]) {
        var login = URLRequest(url: URL(string: Self.server + "/login")!)
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.setValue("true", forHTTPHeaderField: "x-return-tokens")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["username": "qa", "password": "qa-pass"])
        let (body, _) = try await URLSession.shared.data(for: login)
        let token = try XCTUnwrap(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["user"] as? [String: Any])?["accessToken"] as? String)
        var request = URLRequest(url: URL(string: Self.server + path)!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    private func serverTime(_ path: String) async throws -> Double {
        let (status, body) = try await get("/api/me/progress/" + path)
        return status == 200 ? (body["currentTime"] as? Double ?? 0) : 0
    }

    private func waitForServerTime(_ path: String, above floor: Double, timeout: TimeInterval = 30) async throws -> Double {
        let deadline = Date().addingTimeInterval(timeout)
        var value = 0.0
        while Date() < deadline {
            value = try await serverTime(path)
            if value > floor { return value }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("Server progress for \(path) stayed at \(value), not above \(floor)")
        return value
    }

    private func realSignIn() {
        launch(reset: true)
        enter(Self.server, into: app.textFields["serverURL"])
        enter("qa", into: app.textFields["username"])
        enter("qa-pass", into: app.secureTextFields["password"])
        select(app.buttons["connect"])
    }

    /// Continue Listening carries the position another client saved (the phone left it in the last file); playback
    /// resumes there, moves back a chapter into the previous file, and the server records the TV's position there.
    func test1ResumeAnotherClientsPositionAndCrossFiles() async throws {
        let before = try await serverTime(Self.longTide)
        XCTAssertGreaterThan(before, 60, "A position in the last file must be saved first")
        realSignIn()
        let resume = app.buttons["continue-listening.\(Self.longTide)"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30), app.debugDescription)
        capture("real-server-tv-home")
        select(resume)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "The Long Tide")
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 30)
        XCTAssertEqual(label("now-playing-title"), "The Long Tide")
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        let resumedAt = seconds("now-playing-elapsed")
        let chapter = app.staticTexts["now-playing-chapter"]
        let resumedChapter = chapter.label
        capture("real-server-tv-now-playing")
        // More than 3 s into a chapter, Previous restarts it first, so press until the second chapter shows.
        var reachedSecond = false
        for _ in 0..<3 where !reachedSecond {
            select(app.buttons["previous-chapter"])
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Chapter 2 of 3"), object: chapter)
            reachedSecond = XCTWaiter.wait(for: [moved], timeout: 5) == .completed
        }
        let movedChapter = chapter.label
        remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Playing")
        sleep(4)
        select(app.buttons["stop-playback"])
        var saved = before
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            saved = try await serverTime(Self.longTide)
            if saved >= 30, saved < 60 { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        print("TV_RESUME before=\(before) resumedAt=\(resumedAt) resumedChapter=\(resumedChapter) chapter=\(movedChapter) reachedSecond=\(reachedSecond) saved=\(saved)")
        XCTAssertLessThanOrEqual(abs(Double(resumedAt) - before), 3, "The TV must resume at the server position \(before), showed \(resumedAt)")
        XCTAssertTrue(resumedChapter.contains("Chapter 3 of 3"), resumedChapter)
        XCTAssertTrue(reachedSecond, "Previous chapter must move into the second file: \(movedChapter)")
        XCTAssertTrue(saved >= 30 && saved < 60, "The server must record the TV's position in the second file, has \(saved)")
    }

    /// Server search finds a title, and a podcast episode plays and saves episode-level progress.
    func test2SearchAndPodcastEpisode() async throws {
        let (_, podcast) = try await get("/api/items/\(Self.eveningStories)?expanded=1")
        let episodes = try XCTUnwrap((podcast["media"] as? [String: Any])?["episodes"] as? [[String: Any]])
        realSignIn()
        XCTAssertTrue(app.tabBars.buttons["Search"].waitForExistence(timeout: 30))
        tab("Search")
        search("Salt and")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'search.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        select(result)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(label("detail-title"), "Salt and Signal")
        remote.press(.menu)
        tab("Podcasts")
        select(app.buttons["item-" + Self.eveningStories])
        let ids = episodes.compactMap { $0["id"] as? String }
        let row = app.buttons.matching(NSPredicate(format: "identifier IN %@", ids.map { "episode-" + $0 })).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        let episode = String(row.identifier.dropFirst("episode-".count))
        let before = try await serverTime("\(Self.eveningStories)/\(episode)")
        select(row)
        select(app.buttons["play-episode"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 30)
        sleep(5)
        select(app.buttons["stop-playback"])
        let saved = try await waitForServerTime("\(Self.eveningStories)/\(episode)", above: before + 2)
        print("TV_EPISODE episode=\(episode) before=\(before) saved=\(saved)")
        capture("real-server-tv-podcast")
    }
}
