import XCTest

final class MenuFocusJourney: TVJourney {
    override func launch(reset: Bool) {
        app.launchArguments = ["--reset-tv-state", "--probe-menu"]
        app.launch()
    }
    func testFocusedMenuWhilePlaybackAdvances() async throws {
        try await Fixture.configure("long-audio")
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        let kind = ProcessInfo.processInfo.environment["LOFT_MENU_KIND"] ?? "speed"
        let label: String
        switch kind {
        case "sleep":
            select(app.buttons["sleep-timer"])
            select(menuItem("15 minutes"))
            select(app.buttons["sleep-timer"])
            XCTAssertTrue(menuItem("Turn off sleep timer").waitForExistence(timeout: 5))
            label = "30 minutes"
        case "settings":
            tab("Settings")
            select(app.buttons["skip-back-interval"])
            label = "30 seconds"
        case "sort":
            library("Audiobooks")
            select(app.buttons["library-sort"])
            label = "Title Z–A"
        default:
            select(app.buttons["playback-speed"])
            label = "1.5×"
        }
        focus(menuItem(label))
        sleep(20)
        XCTAssertTrue(hasFocus(menuItem(label)))
        select(menuItem(label))
        if kind == "speed" { wait(app.buttons["playback-speed"], label: "Speed 1.5×") }
        if kind == "settings" { XCTAssertEqual(app.buttons["skip-back-interval"].value as? String, "30 seconds") }
        if kind == "sort" { wait(app.buttons["library-sort"], label: "Sort: Title Z–A") }
    }
}
