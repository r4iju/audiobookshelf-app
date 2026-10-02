import XCTest

@MainActor final class OpenIDJourney: NativeJourney {
    func testChangedAuthorizationStateIsRejectedBeforeOpeningBrowser() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("http://127.0.0.1:19765/abs")
        try await FixtureControl.configure("openid-invalid-provider-state")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        app.buttons["openid-sign-in"].tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 8))
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").webViews.links["Approve sign-in"].exists)
    }

    func testBrowserCancellationRetainsTheExistingSavedAccount() async throws {
        try await FixtureControl.configure("baseline")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs")
        let app = XCUIApplication()
        app.buttons["account"].tap()
        app.buttons["Saved connections"].tap()
        app.buttons["Add server"].tap()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://127.0.0.1:19765/abs")
        try await FixtureControl.configure("openid")
        app.buttons["openid-sign-in"].tap()
        let browser = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        XCTAssertTrue(browser.webViews.links["Approve sign-in"].waitForExistence(timeout: 15))
        XCTAssertTrue(browser.buttons["Cancel"].exists)
        browser.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["connection-error"].label.contains("canceled"))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
    }

    func testInvalidBrowserCallbackCannotCreateAnAccount() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("http://127.0.0.1:19765/abs")
        try await FixtureControl.configure("openid-invalid-state")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        let callbacksBefore = try await fixtureRequests().filter { $0.path == "/auth/openid/callback" }.count
        app.buttons["openid-sign-in"].tap()
        let browser = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let approve = browser.webViews.links["Approve sign-in"]
        XCTAssertTrue(approve.waitForExistence(timeout: 15))
        approve.tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["connection-error"].label.contains("could not be verified"))
        XCTAssertFalse(app.buttons["library-books"].exists)
        let callbacksAfter = try await fixtureRequests().filter { $0.path == "/auth/openid/callback" }.count
        XCTAssertEqual(callbacksAfter, callbacksBefore)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.textFields["server"].waitForExistence(timeout: 10))
    }

    func testBrowserSignInReturnsToNativeLibraryAndRestoresAfterRelaunch() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-preview-account"]
        app.launch()
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("http://127.0.0.1:19765/abs")
        let signIn = app.buttons["openid-sign-in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 3))
        guard signIn.exists else { return }
        try await FixtureControl.configure("openid")
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        signIn.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Continue"].waitForExistence(timeout: 3) {
            springboard.alerts.buttons["Continue"].tap()
        }
        let browser = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let approve = browser.webViews.links["Approve sign-in"]
        XCTAssertTrue(approve.waitForExistence(timeout: 15), browser.debugDescription)
        guard approve.exists else { return }
        approve.tap()
        XCTAssertTrue(app.buttons["library-books"].waitForExistence(timeout: 15))
        app.buttons["library-books"].tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
    }
}
