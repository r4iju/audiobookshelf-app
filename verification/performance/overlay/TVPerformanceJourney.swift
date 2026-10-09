import XCTest
import CoreFoundation

final class PerformanceJourney: TVJourney {
    override func launch(reset: Bool) {
        app.launchArguments = (reset ? ["--reset-tv-state"] : []) + ["--profile-ui"]
        app.launch()
    }

    func testLibraryRemoteScrollingWithArtwork() async throws {
        try await Fixture.configure("long-audio")
        signIn()
        waitForHome()
        tab("Library")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: "loft.performance.start" as CFString), nil, nil, true)
        let options = XCTMeasureOptions(); options.iterationCount = 2
        print("[LOFT-PERF] TV scrolling baseline begins")
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<8 { remote.press(.down) }
            for _ in 0..<8 { remote.press(.up) }
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: "loft.performance.stop" as CFString), nil, nil, true)
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
