import XCTest

/// QA probe, not part of the suite: the production app against an isolated, unmodified Audiobookshelf 2.30.0 container
/// (`web/qa/server.mjs` as `abs-apple-qa` on 19890) with its synthetic library and accounts. Results are read from the
/// server's own API. The offline steps are separate methods so the runner can stop and start the container between them.
@MainActor final class RealServerProbe: NativeJourney {
    /// Seeded ids differ per server; `common.sh` resolves them by title and passes them as `TEST_RUNNER_ABS_RS_*`.
    private static let env = ProcessInfo.processInfo.environment
    static let server = env["ABS_RS_SERVER"] ?? "http://127.0.0.1:19890"
    static let books = env["ABS_RS_BOOKS"] ?? ""
    static let podcasts = env["ABS_RS_PODCASTS"] ?? ""
    static let longTide = env["ABS_RS_LONG_TIDE"] ?? ""
    static let fieldGuide = env["ABS_RS_FIELD_GUIDE"] ?? ""
    static let eveningStories = env["ABS_RS_EVENING_STORIES"] ?? ""

    // MARK: Server API (synthetic account)

    private func token() async throws -> String {
        var request = URLRequest(url: URL(string: Self.server + "/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-return-tokens")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": "qa", "password": "qa-pass"])
        let (data, _) = try await URLSession.shared.data(for: request)
        let user = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["user"] as? [String: Any])
        return try XCTUnwrap(user["accessToken"] as? String)
    }

    private func get(_ path: String) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: Self.server + path)!)
        request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    /// Polls the server's saved progress until `accept` holds.
    private func serverProgress(_ path: String, timeout: TimeInterval = 30, _ accept: ([String: Any]) -> Bool) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [String: Any] = [:]
        while Date() < deadline {
            let (status, body) = try await get("/api/me/progress/" + path)
            if status == 200 { last = body; if accept(body) { return body } }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("Server progress for \(path) never satisfied the check; last: \(last)")
        return last
    }

    private func sessions(for item: String) async throws -> [[String: Any]] {
        let (_, body) = try await get("/api/me/item/listening-sessions/\(item)?itemsPerPage=50&page=0")
        return body["sessions"] as? [[String: Any]] ?? []
    }

    // MARK: App helpers

    private func connect(_ app: XCUIApplication) {
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap(); server.typeText(Self.server)
        app.textFields["username"].tap(); app.textFields["username"].typeText("qa")
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText("qa-pass")
        app.buttons["connect"].tap()
        let library = app.buttons["library-" + Self.books]
        XCTAssertTrue(library.waitForExistence(timeout: 15), app.staticTexts["connection-error"].exists ? app.staticTexts["connection-error"].label : "no library list")
        library.tap()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate(); app.launchArguments = []; app.launch()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    private func seconds(_ element: XCUIElement) -> Int? { Int(element.label.split(separator: " ").first ?? "") }

    // MARK: Cases

    /// Sign-in, restored account, a catalog past the first page, multi-file streaming across a file boundary, and the
    /// server-recorded position and listening time.
    func test1SignInBrowseAndStreamAcrossFiles() async throws {
        let app = XCUIApplication()
        connect(app)
        relaunch(app)
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10), "The account must be restored after relaunch")
        XCTAssertFalse(app.secureTextFields["password"].exists)
        let (_, page) = try await get("/api/libraries/\(Self.books)/items?limit=60&page=1&sort=media.metadata.title")
        let pastFirstPage = try XCTUnwrap((page["results"] as? [[String: Any]])?.first?["id"] as? String)
        XCTAssertEqual(page["total"] as? Int, 69)
        let tide = app.buttons["book-" + Self.longTide]
        reveal(tide, in: app)
        tide.tap()
        XCTAssertTrue(app.staticTexts["Mira Vale"].firstMatch.waitForExistence(timeout: 10) || app.staticTexts["By Mira Vale"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Read PDF"].exists, "The PDF ebook must be offered")
        capture("real-server-book-details")
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 15))
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 15))
        for _ in 0..<3 { app.buttons["Forward 10 seconds"].tap() }
        XCTAssertTrue(app.staticTexts["File 2 of 3"].waitForExistence(timeout: 15), "Playback must cross into the second file")
        try await Task.sleep(nanoseconds: 4_000_000_000)
        app.buttons["pause-playback"].tap()
        let position = try XCTUnwrap(seconds(bookElapsed(app)))
        XCTAssertGreaterThanOrEqual(position, 30)
        capture("real-server-player")
        app.buttons["Close playback"].tap()
        let progress = try await serverProgress(Self.longTide) { (($0["currentTime"] as? Double) ?? 0) >= 30 }
        XCTAssertEqual((progress["currentTime"] as? Double).map { abs($0 - Double(position)) <= 3 }, true, "server \(progress["currentTime"] ?? "nil") vs app \(position)")
        let listened = try await sessions(for: Self.longTide).compactMap { $0["timeListening"] as? Double }.reduce(0, +)
        XCTAssertGreaterThan(listened, 0, "The server must record listening time")
        // A catalog row from the server's second page is reachable in the app.
        app.navigationBars.buttons.firstMatch.tap()
        let later = app.buttons["book-" + pastFirstPage]
        reveal(later, in: app)
        XCTAssertTrue(later.exists, "An item beyond the first page must be reachable")
    }

    /// A PDF book opens through the native reader, the page is saved to the server, and relaunch reopens it.
    func test2PDFPageSavedToServerAndRestored() async throws {
        let app = XCUIApplication()
        connect(app)
        let guide = app.buttons["book-" + Self.fieldGuide]
        reveal(guide, in: app)
        guide.tap()
        let read = app.buttons["Read PDF"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        read.tap()
        let first = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Page 1 of '")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "The PDF must render its first page")
        let total = first.label.replacingOccurrences(of: "Page 1 of ", with: "")
        app.buttons["Next page"].tap(); app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of \(total)"].waitForExistence(timeout: 5))
        capture("real-server-pdf")
        app.buttons["Close reader"].tap()
        let saved = try await serverProgress(Self.fieldGuide) { $0["ebookLocation"] as? String != nil && (($0["ebookProgress"] as? Double) ?? 0) > 0 }
        XCTAssertNotNil(saved["ebookLocation"] as? String)
        relaunch(app)
        reveal(app.buttons["book-" + Self.fieldGuide], in: app)
        app.buttons["book-" + Self.fieldGuide].tap()
        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 3 of \(total)"].waitForExistence(timeout: 20), "Relaunch must reopen the saved page")
    }

    /// A podcast episode streams with its own identity, and the server records episode progress.
    func test3PodcastEpisodeProgress() async throws {
        let (_, podcast) = try await get("/api/items/\(Self.eveningStories)?expanded=1")
        let episodes = try XCTUnwrap((podcast["media"] as? [String: Any])?["episodes"] as? [[String: Any]])
        let episode = try XCTUnwrap(episodes.first?["id"] as? String)
        let app = XCUIApplication()
        connect(app)
        app.buttons["account"].tap()
        accountMenu(app).buttons["Change library"].tap()
        app.buttons["library-" + Self.podcasts].tap()
        app.buttons["book-" + Self.eveningStories].tap()
        let row = app.buttons["episode-" + episode]
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 5_000_000_000)
        app.buttons["pause-playback"].tap()
        // A single-file episode without chapters shows only the playback time.
        let position = try XCTUnwrap(seconds(app.staticTexts["playback-elapsed"]))
        XCTAssertGreaterThan(position, 2)
        app.buttons["Close playback"].tap()
        let saved = try await serverProgress("\(Self.eveningStories)/\(episode)") { (($0["currentTime"] as? Double) ?? 0) >= Double(position) - 2 }
        XCTAssertEqual(saved["episodeId"] as? String, episode)
        // 2.30 answers /api/me/progress/<podcast> with an episode's row, so the account's own list is read instead.
        let (_, me) = try await get("/api/me")
        let rows = (me["mediaProgress"] as? [[String: Any]] ?? []).filter { $0["libraryItemId"] as? String == Self.eveningStories }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { ($0["episodeId"] as? String)?.isEmpty == false }, "Episode progress must not be saved as podcast-level progress: \(rows)")
    }

    /// Step 1 of 3: download the multi-file book with its PDF while the server is up.
    func test4aDownloadForOffline() async throws {
        let app = XCUIApplication()
        connect(app)
        let tide = app.buttons["book-" + Self.longTide]
        reveal(tide, in: app)
        tide.tap()
        let download = app.buttons["Download for offline"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["account"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-" + Self.longTide].waitForExistence(timeout: 90), "The download must complete")
        capture("real-server-downloads")
    }

    /// Step 2 of 3, with the server container stopped: the download plays across files and records listening locally.
    func test4bPlayOfflineWithServerStopped() async throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Open downloads"].waitForExistence(timeout: 20), "With the server unreachable the app must offer downloads")
        app.buttons["Open downloads"].tap()
        app.buttons["offline-" + Self.longTide].tap()
        app.buttons["Play offline"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        // The download resumes at the position the server held, so skip only until the third file starts.
        let start = seconds(bookElapsed(app))
        for _ in 0..<6 where !app.staticTexts["File 3 of 3"].exists { app.buttons["Forward 10 seconds"].tap() }
        XCTAssertTrue(app.staticTexts["File 3 of 3"].waitForExistence(timeout: 10), "Offline playback must cross files")
        print("OFFLINE_START=\(start ?? -1)")
        try await Task.sleep(nanoseconds: 4_000_000_000)
        app.buttons["pause-playback"].tap()
        // Past a minute the label shows whole minutes only ("1 min").
        XCTAssertEqual(bookElapsed(app).label, "1 min")
        let position = 60
        capture("real-server-offline-player")
        app.buttons["Close playback"].tap()
        print("OFFLINE_POSITION=\(position)")
    }

    /// Step 3 of 3, server started again: relaunch publishes the offline listening, and the server keeps that position.
    func test4cReconnectPublishesOfflineListening() async throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 30))
        let progress = try await serverProgress(Self.longTide, timeout: 60) { (($0["currentTime"] as? Double) ?? 0) >= 60 }
        XCTAssertGreaterThanOrEqual((progress["currentTime"] as? Double) ?? 0, 60, "The offline position must reach the server")
        let sessions = try await sessions(for: Self.longTide)
        XCTAssertTrue(sessions.contains { ($0["mediaPlayer"] as? String)?.isEmpty == false && (($0["currentTime"] as? Double) ?? 0) >= 60 }, "The offline session must be recorded: \(sessions.map { [$0["currentTime"], $0["timeListening"], $0["playMethod"]] })")
    }

    /// Finish, step 1 of 2, with the server container stopped: the downloaded book plays offline from an unfinished
    /// position to its end.
    func test4dFinishOfflineWithServerStopped() async throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Open downloads"].waitForExistence(timeout: 20), "With the server unreachable the app must offer downloads")
        app.buttons["Open downloads"].tap()
        app.buttons["offline-" + Self.longTide].tap()
        app.buttons["Play offline"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10), "Playback must start from an unfinished position")
        print("FINISH_START=\(bookElapsed(app).label) \(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'File '")).firstMatch.label)")
        for _ in 0..<12 where app.buttons["pause-playback"].exists { app.buttons["Forward 10 seconds"].tap() }
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 20), "Playback must stop at the end of the book")
        XCTAssertTrue(app.staticTexts["File 3 of 3"].exists)
        // At the end the player shows the last file's own time, with nothing left.
        XCTAssertEqual(app.staticTexts["playback-remaining"].label, "−0 sec")
        print("FINISH_END=\(app.staticTexts["playback-elapsed"].label) remaining \(app.staticTexts["playback-remaining"].label)")
        capture("real-server-offline-finished")
        app.buttons["Close playback"].tap()
    }

    /// Finish, step 2 of 2, server started again: relaunch publishes the finished offline session, and the server
    /// reports the book finished at its end.
    func test4eReconnectPublishesTheFinish() async throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 30))
        let progress = try await serverProgress(Self.longTide, timeout: 60) { ($0["isFinished"] as? Bool) == true }
        print("FINISH_SERVER=\(progress)")
        let duration = (progress["duration"] as? Double) ?? 0
        XCTAssertEqual(progress["isFinished"] as? Bool, true, "The server must report the book finished")
        XCTAssertGreaterThanOrEqual((progress["currentTime"] as? Double) ?? 0, duration - 1, "The server position must be the end of the book")
        let sessions = try await sessions(for: Self.longTide)
        XCTAssertTrue(sessions.contains { (($0["currentTime"] as? Double) ?? 0) >= duration - 1 }, "The finished offline session must be recorded")
    }
}
