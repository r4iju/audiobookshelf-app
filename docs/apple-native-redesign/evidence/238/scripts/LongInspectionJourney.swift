import XCTest

/// Capture-only inspection of synthetic long metadata; not a behavioral acceptance test.
final class LongInspectionJourney: TVJourney {
    override func setUp() async throws {
        continueAfterFailure = false
        try await Fixture.configure("baseline")
        var request = URLRequest(url: URL(string: Self.fixture + "/__presentation__/configure")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"mode\":\"long\"}".utf8)
        _ = try await URLSession.shared.data(for: request)
    }
    func testRenderLongMetadata() {
        signIn()
        waitForHome()
        select(app.buttons["continue-listening.book-0"])
        wait(app.staticTexts["detail-title"], label: "A Long Story About Finding Your Way Home Through Unexpected Doors and Forgotten Libraries")
        capture("long-book-top")
        focus(app.staticTexts["detail-description"])
        capture("long-book-description-focused")
        for step in 1...32 {
            remote.press(.down)
            if step % 8 == 0 { capture("long-book-description-down-\(step)") }
        }
        capture("long-book-description-after-down")
        remote.press(.menu)
        tab("Search")
        search("qa")
        select(app.buttons["search.author.author"])
        focus(app.staticTexts["author-bio"])
        capture("long-author-bio-focused")
        for step in 1...16 {
            remote.press(.down)
            if step % 4 == 0 { capture("long-author-bio-down-\(step)") }
        }
        capture("long-author-bio-after-down")
        select(app.buttons["author-series.series-saga"])
        focus(app.staticTexts["series-description"])
        capture("long-series-description-first")
        for step in 1...16 {
            remote.press(.down)
            if step % 4 == 0 { capture("long-series-description-down-\(step)") }
        }
        remote.press(.menu)
        remote.press(.menu)
        library("Podcasts")
        select(app.buttons["item-podcast"])
        select(app.buttons["episode-episode"])
        focus(app.staticTexts["episode-description"])
        capture("long-episode-first")
        for step in 1...16 {
            remote.press(.down)
            if step % 4 == 0 { capture("long-episode-down-\(step)") }
        }
        tab("Settings")
        capture("settings-native-title")
        select(app.buttons["source-notices"])
        focus(app.cells.containing(.staticText, identifier: "notices-origin").firstMatch)
        capture("notices-native-title-origin")
        focus(app.cells.containing(.staticText, identifier: "notices-license").firstMatch)
        capture("notices-native-title-license")
    }
}
