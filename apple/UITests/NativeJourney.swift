import XCTest

@MainActor class NativeJourney: XCTestCase {
    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func capture(_ name: String) {
        let evidence = XCTAttachment(screenshot: XCUIApplication().screenshot())
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func connectSelectAndRestore(serverURL: String, verifyRestoration: Bool = true) {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText(serverURL)
        let username = app.textFields["username"]
        username.tap()
        username.typeText("qa")
        let password = app.secureTextFields["password"]
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

    struct ObservedRequest: Decodable {
        let path: String
        let page: String?
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
    }
    struct LocalSessionObservation: Decodable {
        let id: String
        let currentTime: Double
        let timeListening: Double
    }
    func fixtureRequests() async throws -> [ObservedRequest] {
        try await fixtureObservations().requests
    }
    func fixtureObservations() async throws -> Observations {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:19765/abs/__fixture__/observations")!)
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
}
