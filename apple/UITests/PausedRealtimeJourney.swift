import XCTest

/// Uses the owned realtime fixture, exercising the root event-to-player call sites rather than just the hooks.
@MainActor final class PausedRealtimeJourney: NativeJourney {
    private static let server = "http://127.0.0.1:26765/abs"

    func testAnotherClientsProgressMovesThePausedPlayerWithoutStartingAudio() async throws {
        let app = try await openPausedPlayer()
        // A pause can still be saving its own listening. A later event must follow once that save has settled.
        for _ in 0..<8 {
            try await post("remote-change", ["change": "progress", "itemId": "book-0", "currentTime": 14])
            if app.staticTexts["total-elapsed"].label == "14 sec" { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertEqual(app.staticTexts["total-elapsed"].label, "14 sec")
        XCTAssertTrue(app.buttons["resume-playback"].exists)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(app.staticTexts["total-elapsed"].label, "14 sec")
        capture("paused-player-follows-remote-progress")
    }

    func testReconnectionRefreshesThePausedPositionMissedWhileDisconnected() async throws {
        let app = try await openPausedPlayer()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await post("remote-change", ["change": "silent-progress", "itemId": "book-0", "currentTime": 16])
        try await post("remote-change", ["change": "disconnect"])
        let position = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "16 sec"), object: app.staticTexts["total-elapsed"])
        await fulfillment(of: [position], timeout: 15)
        XCTAssertTrue(app.buttons["resume-playback"].exists)
        XCTAssertEqual(app.staticTexts["playback-status"].label, "Paused")
    }

    private func openPausedPlayer() async throws -> XCUIApplication {
        try await post("configure", ["mode": "baseline"])
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        app.buttons["pause-playback"].tap()
        XCTAssertTrue(app.buttons["resume-playback"].waitForExistence(timeout: 5))
        return app
    }

    private func post(_ path: String, _ body: [String: Any]) async throws {
        var request = URLRequest(url: URL(string: Self.server + "/__fixture__/" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
