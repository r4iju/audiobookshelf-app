import XCTest

@MainActor final class DurableProgressJourney: NativeJourney {
    func testCanceledPreparationCannotOverwriteAnotherClientsNewerPosition() async throws {
        try await FixtureControl.configure("slow-session")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        app.buttons["Close playback"].tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 3))
        try await FixtureControl.configure("newer-remote")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["play-book"])
        await fulfillment(of: [finished], timeout: 12)
        let resumed = try await independentlyResumedPosition()
        XCTAssertEqual(resumed, 19)
    }

    func testRecoveredListeningPreservesNewerProgressAndANewClientResumesIt() async throws {
        try await FixtureControl.configure("offline-progress")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 14
        }, object: bookElapsed(app))
        await fulfillment(of: [listened], timeout: 20)
        app.buttons["pause-playback"].tap()
        XCTAssertTrue(app.staticTexts["playback-error"].waitForExistence(timeout: 10))
        app.terminate()
        try await FixtureControl.configure("newer-remote")
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        // A separate HTTP consumer signs in and opens a stream after journal recovery.
        // Its position comes from the server, independently of the native player's UI state.
        let resumed = try await independentlyResumedPosition()
        XCTAssertEqual(resumed, 19)
        let observations = try await fixtureObservations()
        XCTAssertTrue(observations.reports.contains { $0.path == "/api/session/local-all" && $0.currentTime >= 14 && $0.timeListened > 0 })
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        let afterRestart = try await fixtureObservations()
        XCTAssertEqual(afterRestart.reports.filter { $0.path == "/api/session/local-all" }.count,
                       observations.reports.filter { $0.path == "/api/session/local-all" }.count)
    }

    private func independentlyResumedPosition() async throws -> Double {
        func post(_ path: String, body: [String: String], token: String? = nil, refresh: String? = nil) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs" + path)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            if let refresh { request.setValue(refresh, forHTTPHeaderField: "x-refresh-token") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let login = try await post("/login", body: ["username": "qa", "password": "qa"])
        var user = try XCTUnwrap(login["user"] as? [String: Any])
        if let refresh = user["refreshToken"] as? String {
            let refreshed = try await post("/auth/refresh", body: [:], refresh: refresh)
            user = try XCTUnwrap(refreshed["user"] as? [String: Any])
        }
        let token = try XCTUnwrap((user["accessToken"] ?? user["token"]) as? String)
        let stream = try await post("/api/items/book-0/play", body: [:], token: token)
        let id = try XCTUnwrap(stream["id"] as? String)
        let position = try XCTUnwrap(stream["currentTime"] as? Double)
        _ = try await post("/api/session/" + id + "/close", body: [:], token: token)
        return position
    }

    func testRetryAfterLostAcknowledgmentDoesNotDuplicateListening() async throws {
        try await FixtureControl.configure("baseline")
        try await FixtureControl.configure("lost-ack")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.staticTexts["playback-error"].waitForExistence(timeout: 10))
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 10
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [listened], timeout: 15)
        app.buttons["pause-playback"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["playback-error"])
        await fulfillment(of: [cleared], timeout: 5)
        let observations = try await fixtureObservations()
        let records = observations.localSessions.filter { $0.currentTime >= 10 && $0.timeListening > 0 }
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.timeListening, record.currentTime - 6, accuracy: 1)
        XCTAssertGreaterThanOrEqual(observations.reports.filter { $0.path == "/api/session/local-all" }.count, 2)
    }

    func testUnsentListeningSurvivesTerminationAndRestoresServerProgress() async throws {
        try await FixtureControl.configure("offline-progress")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        let elapsed = bookElapsed(app)
        let listened = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 14
        }, object: elapsed)
        await fulfillment(of: [listened], timeout: 20)
        app.buttons["pause-playback"].tap()
        XCTAssertTrue(app.staticTexts["playback-error"].waitForExistence(timeout: 10))
        app.terminate()
        try await FixtureControl.configure("baseline")
        app.launchArguments = []
        app.launch()
        let firstBook = app.buttons["book-book-0"]
        XCTAssertTrue(firstBook.waitForExistence(timeout: 10))
        firstBook.tap()
        app.buttons["play-book"].tap()
        app.buttons["mini-player"].tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let seconds = Int(element.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 14
        }, object: bookElapsed(app))
        await fulfillment(of: [resumed], timeout: 3)
        let reports = try await fixtureObservations().reports
        XCTAssertTrue(reports.contains { $0.currentTime >= 14 && $0.timeListened > 0 })
    }
}
