import XCTest

/// A login the server revokes while a book streams. Run through `apple/scripts/verify-playback-authorization.sh`
/// with `ABS_PLAYBACK_QA_SCHEME=AudiobookshelfNative`, which starts the fixture and passes its address.
@MainActor final class PlaybackAuthorizationJourney: NativeJourney {
    private var fixture: String!

    override func setUp() async throws {
        guard let address = ProcessInfo.processInfo.environment["ABS_PLAYBACK_FIXTURE"] else {
            throw XCTSkip("Needs the synthetic fixture started by verify-playback-authorization.sh")
        }
        fixture = address
        try await control("configure", ["mode": "baseline"])
    }

    private func control(_ name: String, _ body: [String: String]) async throws {
        var request = URLRequest(url: URL(string: fixture + "/__fixture__/" + name)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func reports() async throws -> [ProgressObservation] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: fixture + "/__fixture__/observations")!)
        return try JSONDecoder().decode(Observations.self, from: data).reports.filter { $0.path == "/api/session/local-all" }
    }

    private func seconds(_ element: XCUIElement) -> Int? { Int(element.label.split(separator: " ").first ?? "") }

    func testRevokedLoginStopsPlaybackAndSigningInAgainDeliversItsListening() async throws {
        connectSelectAndRestore(serverURL: fixture, verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 15))
        // Revoked while the book plays. Buffered audio stops at the next server contact, a file load or a sync, which
        // here can be the end of the 20 s fixture book; PlaybackAuthorizationTests pins the stop at a file boundary.
        try await control("revoke", ["username": "qa"])

        let signIn = app.buttons["sign-in-again"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20), "No way to sign in again")
        XCTAssertEqual(app.staticTexts["playback-status"].label, "Paused")
        let stoppedAt = try XCTUnwrap(seconds(app.staticTexts["playback-elapsed"]))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(seconds(app.staticTexts["playback-elapsed"]), stoppedAt, "Audio kept playing for a revoked login")
        capture("Revoked login while listening")

        signIn.tap()
        let password = app.secureTextFields["password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["username"].value as? String, "qa")
        XCTAssertTrue(app.staticTexts["connection-error"].exists)
        capture("Sign in again")
        password.tap()
        password.typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 15))

        let delivered = try await reports().last { $0.userId == "00000000-0000-4000-8000-000000000001" }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(delivered, "Listening was lost").currentTime, Double(stoppedAt))
    }
}
