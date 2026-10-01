import XCTest

final class ConnectionJourney: XCTestCase {
    func testConnectSelectLibraryAndRestoreAccountAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("http://127.0.0.1:18765/abs")
        let username = app.textFields["username"]
        username.tap()
        username.typeText("qa")
        let password = app.secureTextFields["password"]
        password.tap()
        password.typeText("qa")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 10))
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
