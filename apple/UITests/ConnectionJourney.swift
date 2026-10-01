import XCTest

final class ConnectionJourney: XCTestCase {
    func testConnectSelectLibraryAndRestoreAccountAfterRelaunch() {
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
    }

    func testQualifiedLANHTTPConnectsWithoutWeakeningHTTPSTrust() {
        connectSelectAndRestore(serverURL: "http://dev.nginx.lan:19765/abs")
        let app = XCUIApplication()
        app.buttons["Sign out"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        if let current = server.value as? String {
            server.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        server.typeText("https://dev.nginx.lan:19767/abs")
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("qa")
        app.buttons["connect"].tap()
        let error = app.staticTexts["connection-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("certificate") || error.label.contains("TLS"))
        XCTAssertFalse(app.buttons["library-books"].exists)
    }

    private func connectSelectAndRestore(serverURL: String) {
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
        XCTAssertTrue(app.staticTexts["Audiobooks"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields["password"].exists)
    }

    func testInvalidServerShowsRecoveryWithoutLeavingConnectionForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("file:///tmp/books")
        app.textFields["username"].tap()
        app.textFields["username"].typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["server"].exists)
        XCTAssertEqual(app.textFields["server"].value as? String, "file:///tmp/books")
    }
}
