import XCTest

/// Synthetic render orchestration only. Existing journeys retain behavioral acceptance assertions.
final class RenderJourney: TVJourney {
    override func setUp() async throws {
        continueAfterFailure = false
        try await Fixture.configure("baseline")
        try await presentation("baseline")
    }
    func presentation(_ mode: String) async throws {
        var r = URLRequest(url: URL(string: Self.fixture + "/__presentation__/configure")!)
        r.httpMethod = "POST"; r.httpBody = Data("{\"mode\":\"\(mode)\"}".utf8)
        _ = try await URLSession.shared.data(for: r)
    }
    func shot(_ name: String) { usleep(450_000); capture(name) }
    func testRenderSignInKeyboardAndFailure() {
        launch(reset: true); shot("signin-initial")
        select(app.textFields["serverURL"]); shot("signin-server-keyboard")
        remote.press(.menu)
        if app.keyboards.firstMatch.exists && app.keyboards.firstMatch.hasFocus { remote.press(.menu) }
        enter("http://127.0.0.1:\(Self.port("ABS_TV_HTTP_PORT", 33775) + 34)/abs", into: app.textFields["serverURL"])
        enter("qa", into: app.textFields["username"])
        enter("qa", into: app.secureTextFields["password"])
        select(app.buttons["connect"]); sleep(2); shot("signin-unreachable-error")
    }
    func testRenderUnbrokenMetadata() async throws {
        try await presentation("unbroken")
        signIn(); waitForHome(); select(app.buttons["continue-listening.book-0"])
        focus(app.staticTexts["detail-description"]); shot("unbroken-description-first")
        for step in 1...8 {
            remote.press(.down)
            if step == 2 || step == 8 { shot("unbroken-description-down-\(step)") }
        }
    }
    func testRenderSignoutWithUnsentListening() async throws {
        try await Fixture.configure("offline-progress")
        signIn(); waitForHome(); select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        sleep(3); remote.press(.playPause)
        wait(app.staticTexts["playback-status"], label: "Paused")
        tab("Settings"); select(app.buttons["sign-out"]); sleep(2)
        shot("settings-signout-unsent-error")
    }
    func testRenderAuthenticationRecoveryAlertAndKeyboard() async throws {
        signIn(); waitForHome(); select(app.buttons["continue-listening.book-0"])
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        try await Fixture.revoke("qa"); remote.press(.playPause)
        let alert = app.alerts["Sign in again"].firstMatch
        _ = alert.waitForExistence(timeout: 10); shot("auth-expired-native-alert")
        select(alert.buttons["Sign in"].firstMatch); shot("auth-fullscreen-form")
        select(app.secureTextFields["password"]); shot("auth-password-native-keyboard")
        remote.press(.menu)
        if app.keyboards.firstMatch.exists && app.keyboards.firstMatch.hasFocus { remote.press(.menu) }
        remote.press(.menu); shot("auth-dismissal-preserved-player")
    }
    func testRenderCatalogFailureAndRetry() async throws {
        try await Fixture.configure("offline-library")
        signIn(); _ = app.buttons["retry-catalog"].waitForExistence(timeout: 20)
        shot("catalog-service-failure")
        try await Fixture.configure("baseline")
        select(app.buttons["retry-catalog"]); waitForHome(); shot("catalog-service-recovered")
    }
    func testRenderPlayerPanelsAndListeningPreferences() {
        signIn(); waitForHome(); shot("listen-now-overview")
        select(app.buttons["continue-listening.book-0"])
        focus(app.buttons["play-item"]); shot("book-primary-focused")
        select(app.buttons["play-item"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        remote.press(.playPause); wait(app.staticTexts["playback-status"], label: "Paused")
        shot("player-paused-overview")
        select(app.buttons["chapters"]); shot("chapters-current")
        focus(app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Next chapter")).firstMatch)
        shot("chapters-last-focused"); remote.press(.menu)
        select(app.buttons["playback-speed"]); shot("speed-options")
        focus(menuItem("3×")); shot("speed-last-focused"); remote.press(.menu)
        select(app.buttons["sleep-timer"]); shot("sleep-duration-options")
        select(menuItem("End of chapter")); shot("sleep-chapter-active")
        select(app.buttons["sleep-timer"]); shot("sleep-active-cancel-option")
        select(menuItem("Turn off sleep timer"))
        select(app.buttons["sleep-timer"]); select(menuItem("15 minutes")); shot("sleep-duration-active")
        select(app.buttons["sleep-timer"]); select(menuItem("Turn off sleep timer"))
        tab("Settings"); shot("settings-with-session-top")
        select(app.buttons["skip-back-interval"]); shot("settings-skip-back-options")
        focus(menuItem("60 seconds")); shot("settings-skip-back-last"); remote.press(.menu)
        select(app.buttons["skip-forward-interval"]); shot("settings-skip-forward-options"); remote.press(.menu)
        focus(app.buttons["sign-out"]); shot("settings-listening-account-bottom")
        tab("Now Playing"); select(app.buttons["stop-playback"])
        sleep(2); shot("shell-after-explicit-stop")
    }
    func testRenderNativeSettingsLanguageAndNotices() {
        signIn(); waitForHome(); tab("Settings"); shot("settings-top")
        focus(app.staticTexts["auth-modes"]); shot("settings-supported-signin-focused")
        select(app.buttons["source-notices"]); shot("notices-overview")
        focus(app.cells.containing(.staticText, identifier: "notices-origin").firstMatch); shot("notices-origin-focus")
        focus(app.cells.containing(.staticText, identifier: "notices-license").firstMatch); shot("notices-license-focus")
        remote.press(.menu); shot("notices-back-restored")
        let language = app.buttons["language-setting"]
        for _ in 0..<24 where language.frame.isEmpty || !app.windows.firstMatch.frame.intersects(language.frame) { remote.press(.up) }
        select(language); shot("language-top-selected")
        focus(app.buttons["language-zh-Hans"]); shot("language-list-end")
        remote.press(.menu)
        select(app.buttons["diagnostics-setting"]); shot("diagnostics-empty-masked")
        select(app.descendants(matching: .any)["diagnostic-show-address"].firstMatch); shot("diagnostics-address-revealed")
        remote.press(.menu); focus(app.buttons["sign-out"]); shot("settings-signout-focused")
    }
    func testRenderPodcastAndEpisode() {
        signIn(); waitForHome(); library("Podcasts"); shot("podcast-library")
        select(app.buttons["item-podcast"])
        focus(app.buttons["episode-episode-morning"]); shot("podcast-newest-episode-focused")
        select(app.buttons["episode-sort"]); shot("podcast-oldest-first")
        select(app.buttons["episode-episode"])
        focus(app.buttons["play-episode"]); shot("episode-play-focused")
        // The stock evening episode has no description; the separate long fixture supplies one.
        if app.staticTexts["episode-description"].exists {
            focus(app.staticTexts["episode-description"]); shot("episode-description-focused")
        }
        select(app.buttons["play-episode"])
        wait(app.staticTexts["playback-status"], label: "Playing", timeout: 20)
        remote.press(.playPause); wait(app.staticTexts["playback-status"], label: "Paused")
        shot("episode-player-paused")
        select(app.buttons["stop-playback"])
    }
    func testRenderLibrarySortFilter() {
        signIn(); waitForHome(); tab("Library")
        shot("library-overview")
        select(app.buttons["library-sort"]); shot("library-sort-options"); remote.press(.menu)
        select(app.buttons["library-filter"]); shot("library-filter-options")
        select(menuItem("Finished")); sleep(2); shot("library-filter-empty")
        select(app.buttons["library-filter"]); select(menuItem("All titles"))
        focus(app.buttons["item-book-1"]); shot("portrait-cover-focused")
        select(app.buttons["item-book-1"]); shot("portrait-cover-detail")
    }
    func testRenderSearchGroupedResults() {
        signIn(); waitForHome(); tab("Search"); shot("search-native-keyboard-prompt")
        search("qa"); sleep(2); shot("search-authors-group-keyboard")
        focus(app.buttons["search.author.author"]); shot("search-author-focused")
        select(app.buttons["search.author.author"]); shot("author-overview")
        select(app.buttons["author-series.series-saga"]); shot("series-overview")
        focus(app.buttons["series-book.book-9"]); shot("series-book-focused")
    }
    func testRenderSearchEpisodes() {
        signIn(); waitForHome(); tab("Search"); search("Quiet"); sleep(2)
        shot("search-episode-group-keyboard")
        focus(app.buttons["search.podcast.episode"]); shot("search-episode-focused")
    }
    func testRenderSearchEmpty() {
        signIn(); waitForHome(); tab("Search"); search("unmatched synthetic query"); sleep(2)
        shot("search-no-results-keyboard")
    }
    func testRenderSearchFailureAndRetry() async throws {
        signIn(); waitForHome(); tab("Search")
        try await Fixture.configure("offline-library")
        search("Quiet"); sleep(2); shot("search-failure-keyboard")
        try await Fixture.configure("baseline")
        select(app.buttons["retry-search"]); sleep(2); shot("search-retry-results")
    }
    func testRenderSearchLoading() async throws {
        signIn(); waitForHome(); tab("Search")
        try await presentation("loading"); search("Quiet"); shot("search-loading-keyboard")
        sleep(8); shot("search-after-loading")
    }
    func testRenderMissingArtworkAndEmptyPodcast() async throws {
        try await presentation("missing-art")
        signIn(); waitForHome(); shot("listen-now-missing-art")
        select(app.buttons["continue-listening.book-0"]); shot("book-missing-art")
        remote.press(.menu); tab("Search"); search("qa")
        select(app.buttons["search.author.author"]); shot("author-missing-image")
        remote.press(.menu); library("Podcasts")
        try await presentation("empty-podcast")
        select(app.buttons["item-podcast"]); sleep(1); shot("podcast-empty-episodes")
    }
    func testRenderDetailLoadingFailureAndLibraryEmpty() async throws {
        signIn(); waitForHome(); try await presentation("loading")
        select(app.buttons["continue-listening.book-0"]); shot("book-loading-context")
        sleep(5); shot("book-loaded")
        remote.press(.menu); try await presentation("detail-error")
        select(app.buttons["continue-listening.book-0"]); sleep(1); shot("book-detail-failure")
        try await presentation("baseline"); try await Fixture.configure("empty")
        signIn(); sleep(2); shot("listen-now-empty")
        tab("Library"); sleep(2); shot("library-empty")
    }
}
