import XCTest

/// Opens the app's URLs through the system for scripts/legacy-app-url-check.sh.
final class OpenURLThroughSystem: XCTestCase {
    func testOpenTheURL() throws {
        let url = try XCTUnwrap(ProcessInfo.processInfo.environment["ABS_LEGACY_URL"].flatMap(URL.init(string:)))
        XCUIDevice.shared.system.open(url)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 5) { open.tap() }
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.audiobookshelf.app.dev").wait(for: .runningForeground, timeout: 15))
    }
}
