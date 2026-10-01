import XCTest

/// Drives the production TV app only through the Siri Remote and the synthetic fixture.
@MainActor class TVJourney: XCTestCase {
    static let fixture = "http://127.0.0.1:\(port("ABS_TV_HTTP_PORT", 20765))/abs"
    static let secureFixture = "https://127.0.0.1:\(port("ABS_TV_HTTPS_PORT", 20767))/abs"

    /// `verify-ui.sh` passes the ports it served, so parallel worktrees can use their own.
    static func port(_ name: String, _ standard: Int) -> Int {
        ProcessInfo.processInfo.environment[name].flatMap(Int.init) ?? standard
    }
    let app = XCUIApplication()
    let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
        try await Fixture.configure("baseline")
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func capture(_ name: String) {
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func launch(reset: Bool) {
        app.launchArguments = reset ? ["--reset-tv-state"] : []
        app.launch()
    }

    var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Moves focus with directional presses toward the element, as a person would.
    func focus(_ element: XCUIElement, presses: Int = 40, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(element)", file: file, line: line)
        for _ in 0..<presses {
            if hasFocus(element) { return }
            let from = focused.frame, to = element.frame
            if from.isEmpty || to.isEmpty { remote.press(.down); continue }
            let dx = to.midX - from.midX, dy = to.midY - from.midY
            if abs(dy) > max(from.height, to.height) / 2 { remote.press(dy > 0 ? .down : .up) }
            else { remote.press(dx > 0 ? .right : .left) }
        }
        XCTFail("Could not move focus to \(element); focused \(focused.debugDescription)", file: file, line: line)
    }

    /// SwiftUI menus report focus on an inner element rather than the identified button.
    func hasFocus(_ element: XCUIElement) -> Bool {
        element.hasFocus || element.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).count > 0
    }

    func select(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        focus(element, file: file, line: line)
        remote.press(.select)
    }

    func enter(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        select(field, file: file, line: line)
        app.typeText(text)
        remote.press(.menu)
    }

    /// An option in an open menu, found by the text the person reads (sections drop identifiers).
    func menuItem(_ label: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Moves focus from the search field into the on-screen keyboard and types there.
    func search(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        let keyboard = app.keyboards.firstMatch
        for _ in 0..<4 where !(keyboard.exists && keyboard.hasFocus) { remote.press(.down) }
        XCTAssertTrue(keyboard.hasFocus, "The search keyboard should take focus", file: file, line: line)
        app.typeText(text)
    }

    func signIn(server: String = TVJourney.fixture, reset: Bool = true) {
        launch(reset: reset)
        enter(server, into: app.textFields["serverURL"])
        enter("qa", into: app.textFields["username"])
        enter("qa", into: app.secureTextFields["password"])
        select(app.buttons["connect"])
    }

    func tab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        select(app.tabBars.buttons[name], file: file, line: line)
    }

    func waitForHome(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["continue-listening.book-0"].waitForExistence(timeout: 20), app.debugDescription, file: file, line: line)
    }

    func label(_ identifier: String) -> String { app.staticTexts[identifier].label }

    func wait(_ element: XCUIElement, label expected: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matched], timeout: timeout), .completed, "Expected \(expected), saw \(element.exists ? element.label : "nothing")", file: file, line: line)
    }

    /// Seconds parsed from an m:ss or h:mm:ss clock label.
    func seconds(_ identifier: String) -> Int {
        label(identifier).split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    func observations() async throws -> Fixture.Observations { try await Fixture.observations() }
}

enum Fixture {
    static func configure(_ mode: String, base: String = TVJourney.fixture) async throws {
        var request = URLRequest(url: URL(string: base + "/__fixture__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["mode": mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Fixture on \(base) rejected mode \(mode)")
    }

    struct Request: Decodable { let method: String?; let path: String; let page: String? }
    struct Report: Decodable { let path: String; let currentTime: Double; let timeListened: Double; let sessionId: String? }
    struct LocalSession: Decodable { let id: String; let currentTime: Double; let timeListening: Double; let libraryItemId: String; let episodeId: String? }
    struct Observations: Decodable {
        let requests: [Request]
        let reports: [Report]
        let localSessions: [LocalSession]
    }

    static func observations(base: String = TVJourney.fixture) async throws -> Observations {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/__fixture__/observations")!)
        return try JSONDecoder().decode(Observations.self, from: data)
    }
}
