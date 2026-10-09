import XCTest
import CoreFoundation

@MainActor final class PerformanceJourney: NativeJourney {
    func testLibraryScrollingWithLoadedArtwork() async throws {
        try await FixtureControl.configure("long-audio")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false, arguments: ["--profile-ui"])
        let app = XCUIApplication()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        app.buttons["book-book-0"].tap()
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["book-book-0"].waitForExistence(timeout: 10))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        print("[LOFT-PERF] native scrolling baseline begins")
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: "loft.performance.start" as CFString), nil, nil, true)
            Thread.sleep(forTimeInterval: 15)
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: "loft.performance.stop" as CFString), nil, nil, true)
            Thread.sleep(forTimeInterval: 0.5)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
