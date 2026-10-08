import XCTest

@MainActor class NativeJourney: XCTestCase {
    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    /// The open account menu. The iPad library sidebar repeats "Change library", so the menu is the collection outside it.
    func accountMenu(_ app: XCUIApplication) -> XCUIElementQuery {
        app.collectionViews.matching(NSPredicate(format: "label != %@", "Sidebar"))
    }

    func librarySearchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields["library-search"]
        return field.exists ? field : app.searchFields.firstMatch
    }

    func capture(_ name: String) {
        let evidence = XCTAttachment(screenshot: XCUIApplication().screenshot())
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func connectSelectAndRestore(serverURL: String, verifyRestoration: Bool = true, arguments: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"] + arguments
        app.launch()
        let server = app.textFields["server"]
        for _ in 0..<5 where !server.exists { app.swipeUp() }
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText(serverURL)
        let username = app.textFields["username"]
        for _ in 0..<3 where !username.exists { app.swipeUp() }
        username.tap()
        username.typeText("qa")
        let password = app.secureTextFields["password"]
        for _ in 0..<3 where !password.exists { app.swipeUp() }
        password.tap()
        password.typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 10), app.staticTexts["connection-error"].exists ? app.staticTexts["connection-error"].label : app.debugDescription)
        app.buttons["library-books"].tap()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        guard verifyRestoration else { return }
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields["password"].exists)
    }

    func openPlayerSettings(_ app: XCUIApplication) {
        let open = app.buttons["Playback settings"]
        for _ in 0..<3 where !(open.exists && open.isHittable) { app.swipeUp() }
        open.tap()
    }

    /// Opens Playback settings, applies the switches in order and closes the panel.
    func playerSettings(_ app: XCUIApplication, _ switches: [(String, Bool)]) {
        openPlayerSettings(app)
        for (identifier, on) in switches {
            let toggle = app.switches[identifier]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3), "\(identifier) is missing from Playback settings")
            if (toggle.value as? String == "1") != on { toggle.switches.firstMatch.tap() }
            XCTAssertEqual(toggle.value as? String, on ? "1" : "0", identifier)
        }
        app.buttons["panel-done"].tap()
        waitForPanelToClose(app, "Settings")
        app.swipeDown(); app.swipeDown()
    }

    /// The whole-book position. iOS starts with the chapter track on, where playback-elapsed is the time within the
    /// chapter and the total track beside it shows the book. Both are divided by the playback speed unless that is turned off.
    func bookElapsed(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["total-elapsed"] }
    /// Waits for a dismissed listening panel to leave the screen. On iPad the panel is a form sheet that is still
    /// animating out when the next tap arrives, and UIKit drops a tap made during that transition.
    func waitForPanelToClose(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars[title])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "The \(title) panel is still open", file: file, line: line)
    }


    struct ObservedRequest: Decodable {
        let method: String?
        let path: String
        let page: String?
        let ebookLocation: String?
        let applied: Bool?
    }
    struct ProgressObservation: Decodable {
        let path: String
        let currentTime: Double
        let timeListened: Double
        let userId: String?
    }
    struct Observations: Decodable {
        let requests: [ObservedRequest]
        let reports: [ProgressObservation]
        let localSessions: [LocalSessionObservation]
        let readingProgress: [ReadingObservation]
    }
    struct ReadingObservation: Decodable {
        let libraryItemId: String
        let ebookLocation: String
        let ebookProgress: Double?
        let currentTime: Double?
    }
    struct LocalSessionObservation: Decodable {
        let id: String
        let currentTime: Double
        let timeListening: Double
    }
    func fixtureRequests() async throws -> [ObservedRequest] {
        try await fixtureObservations().requests
    }
    func fixtureObservations(server: String = "http://127.0.0.1:19765/abs") async throws -> Observations {
        let (data, response) = try await URLSession.shared.data(from: URL(string: server + "/__fixture__/observations")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(Observations.self, from: data)
    }

}

enum FixtureControl {
    static func configure(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs/__fixture__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["mode": mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
    /// Ends whatever the server was still handling, as a restart of the server does.
    static func restart() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:19765/abs/__fixture__/restart")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
