import XCTest

/// A login the server revokes while a book streams. Run through `apple/scripts/verify-playback-authorization.sh`
/// with `ABS_PLAYBACK_QA_SCHEME=AudiobookshelfNative`, which starts the fixture and passes its address.
@MainActor final class PlaybackAuthorizationJourney: NativeJourney {
    /// `ApplePlayback` syncs listening at the first one-second tick 15 s after the previous sync, and a file load or
    /// pause contacts the server sooner. A revoked login must stop audio at that contact: within the sync interval,
    /// plus the tick and the rejected request's round trip, and plus one for the whole seconds the player shows.
    private let syncInterval = 15
    private let contactAllowance = 3
    /// The fixture's `long-audio` book, long enough that no stop can come from reaching its end.
    private let bookDuration = 120
    private let qa = "00000000-0000-4000-8000-000000000001"
    private var fixture: String!

    override func setUp() async throws {
        guard let address = ProcessInfo.processInfo.environment["ABS_PLAYBACK_FIXTURE"] else {
            throw XCTSkip("Needs the synthetic fixture started by verify-playback-authorization.sh")
        }
        fixture = address
        try await control("configure", ["mode": "long-audio"])
    }

    override func tearDown() async throws {
        try? await control("configure", ["mode": "baseline"])
    }

    private func control(_ name: String, _ body: [String: String]) async throws {
        var request = URLRequest(url: URL(string: fixture + "/__fixture__/" + name)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private struct Request: Decodable { let path: String; let status: Int? }
    private struct Report: Decodable { let path: String; let currentTime: Double; let userId: String? }
    private struct Observed: Decodable { let requests: [Request]; let reports: [Report] }

    private func observed() async throws -> Observed {
        let (data, _) = try await URLSession.shared.data(from: URL(string: fixture + "/__fixture__/observations")!)
        return try JSONDecoder().decode(Observed.self, from: data)
    }

    /// The book's elapsed time the full player shows, in whole seconds; it is only that precise below a minute.
    /// (`playback-elapsed` is the chapter's, which restarts at each chapter.)
    private func elapsed(_ app: XCUIApplication) throws -> Int {
        let label = app.staticTexts["total-elapsed"].label
        let parts = label.split(separator: " ")
        return try XCTUnwrap(parts.count == 2 && parts[1] == "sec" ? Int(parts[0]) : nil, "Elapsed time \"\(label)\" is not in seconds")
    }

    private func label(_ element: XCUIElement, becomes value: String, within timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)], timeout: timeout) == .completed
    }

    func testRevokedLoginStopsPlaybackAndSigningInAgainDeliversItsListening() async throws {
        connectSelectAndRestore(serverURL: fixture, verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 15))

        // Audio must be decoding when the server revokes the login: it plays and its position advances.
        let status = app.staticTexts["playback-status"]
        XCTAssertTrue(label(status, becomes: "Playing", within: 10), "Audio was not playing before the revocation")
        let decodingFrom = try elapsed(app)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertGreaterThan(try elapsed(app), decodingFrom, "Audio was not decoding before the revocation")
        let requestsBeforeRevocation = try await observed().requests.count
        try await control("revoke", ["username": "qa"])
        let revokedAt = try elapsed(app)

        let signIn = app.buttons["sign-in-again"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Double(syncInterval + contactAllowance + 2)), "No way to sign in again")
        XCTAssertEqual(status.label, "Paused")
        let stoppedAt = try elapsed(app)
        XCTAssertLessThanOrEqual(stoppedAt, revokedAt + syncInterval + contactAllowance,
                                 "Audio played past the first server contact after the revocation")
        XCTAssertLessThan(stoppedAt + 60, bookDuration, "The stop must come from the revocation, not the end of the book")
        let afterRevocation = try await observed().requests.dropFirst(requestsBeforeRevocation)
        XCTAssertTrue(afterRevocation.contains { $0.status == 401 }, "No server contact rejected the revoked login")
        capture("Revoked login while listening")

        // Nothing starts the audio again for the revoked login: not time passing, and not the play control.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertEqual(try elapsed(app), stoppedAt, "Audio kept playing for a revoked login")
        app.buttons["resume-playback"].tap()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(status.label, "Paused", "The play control started audio for a revoked login")
        XCTAssertEqual(try elapsed(app), stoppedAt)
        XCTAssertTrue(signIn.exists)

        // The prompt signs the same account in again on the same server.
        signIn.tap()
        let password = app.secureTextFields["password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["server"].value as? String, fixture)
        XCTAssertEqual(app.textFields["username"].value as? String, "qa")
        XCTAssertTrue(app.staticTexts["connection-error"].exists)
        capture("Sign in again")
        password.tap()
        password.typeText("qa")
        let requestsBeforeSignIn = try await observed().requests.count
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 15))

        // Signing in delivers the held listening at the stopped position and does not start playing by itself.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertFalse(app.buttons["pause-playback"].exists || app.buttons["mini-pause-playback"].exists, "Audio resumed after signing in")
        let final = try await observed()
        XCTAssertFalse(final.requests.dropFirst(requestsBeforeSignIn).contains { $0.path.hasPrefix("/audio/") }, "Audio loaded again after signing in")
        let delivered = try XCTUnwrap(final.reports.last { $0.userId == qa && $0.path == "/api/session/local-all" }, "Listening was lost")
        XCTAssertGreaterThanOrEqual(delivered.currentTime, Double(stoppedAt))
        XCTAssertLessThan(delivered.currentTime, Double(stoppedAt + 2))
    }
}
