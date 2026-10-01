import XCTest

/// A progress save a gateway gave up on, seen from open book details. Run through
/// `apple/scripts/verify-publication-recovery.sh`, which starts the fixture and passes its address.
@MainActor final class PublicationRecoveryJourney: NativeJourney {
    private var fixture: String!

    override func setUp() async throws {
        guard let address = ProcessInfo.processInfo.environment["ABS_PUBLICATION_FIXTURE"] else {
            throw XCTSkip("Needs the synthetic fixture started by verify-publication-recovery.sh")
        }
        fixture = address
        continueAfterFailure = false
        try await control("configure", ["mode": "held-sync"])
    }

    override func tearDown() async throws {
        try? await control("configure", ["mode": "baseline"])
    }

    private func control(_ name: String, _ body: [String: String] = [:]) async throws {
        var request = URLRequest(url: URL(string: fixture + "/__fixture__/" + name)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private struct Restart: Decodable { let endedHandlers: Int }
    private struct Session: Decodable { let libraryItemId: String; let currentTime: Double; let timeListening: Double }
    private struct Request: Decodable { let method: String?; let path: String }
    private struct Report: Decodable { let path: String }
    private struct Observed: Decodable {
        let heldHandlers: Int
        let serverRestarts: [Restart]
        let localSessions: [Session]
        let requests: [Request]
        let reports: [Report]
        var book: [Session] { localSessions.filter { $0.libraryItemId == "book-0" } }
    }

    private func observed() async throws -> Observed {
        let (data, _) = try await URLSession.shared.data(from: URL(string: fixture + "/__fixture__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data)
    }

    /// Server 2.30 has no request barrier: a save a gateway gave up on may still be applied over anything sent
    /// after it. Details that are open when a background save meets that say so, and later listening waits until
    /// a restart asked for after the save is confirmed.
    func testOpenDetailsOfferARestartOnceASaveGetsNoAnswerAndSendLaterListeningAfterIt() async throws {
        connectSelectAndRestore(serverURL: fixture, verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        let pause = app.buttons["mini-pause-playback"], resume = app.buttons["mini-resume-playback"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(3)
        pause.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        var held = 0
        for _ in 0..<30 where held == 0 {
            try await Task.sleep(nanoseconds: 500_000_000)
            held = try await observed().heldHandlers
        }
        XCTAssertEqual(held, 1, "Precondition: the fixture held the save sent on pause")

        let restart = app.buttons["restart-server"]
        XCTAssertTrue(restart.waitForExistence(timeout: 10), "Open details should offer a server restart once a save got no answer")
        capture("Details after a save got no answer")

        // Later listening stays on this device.
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        sleep(3)
        pause.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        var sessions = try await observed().book
        XCTAssertTrue(sessions.isEmpty, "Later listening was sent while the held save could still be applied")

        // The restart is asked for before the server restarts, then confirmed.
        restart.tap()
        let confirm = app.alerts.buttons["Server restarted"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        capture("Restart asked for")
        try await control("restart")
        let restarted = try await observed()
        XCTAssertEqual(restarted.serverRestarts.map(\.endedHandlers), [1], "Precondition: the restart ended the held save")
        confirm.tap()
        for _ in 0..<30 where sessions.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            sessions = try await observed().book
        }
        let sent = try XCTUnwrap(sessions.first, "The listening that waited was not sent after the confirmed restart")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertGreaterThan(sent.timeListening, 4, "Listening from both plays is kept")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: restart)
        await fulfillment(of: [gone], timeout: 10)
        XCTAssertTrue(resume.exists, "Sending what waited must not start playing")
        XCTAssertFalse(pause.exists)
        let seen = try await observed()
        XCTAssertFalse(seen.requests.contains { $0.method == "DELETE" }, "Recovering must not discard progress")
        XCTAssertEqual(seen.heldHandlers, 0)
        capture("Details after the confirmed restart")

        // Nothing is sent again after a relaunch.
        let reported = seen.reports.count
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let after = try await observed()
        XCTAssertEqual(after.reports.count, reported, "A delivered save must not be sent again")
        XCTAssertEqual(after.book.count, 1)
    }
}
