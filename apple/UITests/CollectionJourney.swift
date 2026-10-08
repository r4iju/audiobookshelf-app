import XCTest

@MainActor final class CollectionJourney: NativeJourney {
    func testDownloadedGroupRefreshesCompletionMadeAfterOpening() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-2"].tap(); app.buttons["Download for offline"].tap()
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-book-2"].waitForExistence(timeout: 45))
        app.navigationBars.buttons["Done"].tap()
        app.buttons["account"].tap(); app.buttons["Collections"].tap()
        XCTAssertTrue(app.buttons["group-collection-evening"].waitForExistence(timeout: 5))
        app.buttons["group-collection-evening"].tap()
        XCTAssertTrue(app.buttons["Play collection"].waitForExistence(timeout: 5))
        let initial = try await fixtureRequests().count
        try await FixtureControl.configure("group-remote-finish")
        app.buttons["Play collection"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 5))
        let requests = try await fixtureRequests().dropFirst(initial)
        XCTAssertTrue(requests.contains { $0.path == "/api/me" }, "Check newer progress before selecting a downloaded group member")
        XCTAssertTrue(requests.contains { $0.path == "/api/items/book-1/play" }, "Skip the downloaded member another client has just completed")
    }
    func testDownloadedCollectionBookPlaysWithoutServerAccess() async throws {
        try await downloadedGroupPlaysOffline(podcast: false)
    }
    func testDownloadedPlaylistEpisodePlaysWithoutServerAccess() async throws {
        try await downloadedGroupPlaysOffline(podcast: true)
    }
    private func downloadedGroupPlaysOffline(podcast: Bool) async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        if podcast {
            app.buttons["account"].tap(); accountMenu(app).buttons["Change library"].tap(); app.buttons["library-podcasts"].tap()
        }
        let item = podcast ? "podcast" : "book-2"
        app.buttons["book-\(item)"].tap()
        if podcast {
            XCTAssertTrue(app.buttons["episode-episode-morning"].waitForExistence(timeout: 5))
            app.buttons["episode-episode-morning"].tap()
        }
        app.buttons["Download for offline"].tap(); app.navigationBars.buttons["BackButton"].tap()
        if podcast { app.navigationBars.buttons["BackButton"].tap() }
        app.buttons["account"].tap(); app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["offline-\(item)"].waitForExistence(timeout: 45))
        app.navigationBars.buttons["Done"].tap()
        app.buttons["account"].tap(); app.buttons[podcast ? "Playlists" : "Collections"].tap()
        let group = podcast ? "playlist-podcasts" : "collection-evening"
        XCTAssertTrue(app.buttons["group-\(group)"].waitForExistence(timeout: 5))
        app.buttons["group-\(group)"].tap()
        let play = app.buttons[podcast ? "Play playlist" : "Play collection"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let initialRequests = try await fixtureRequests().count
        addTeardownBlock { try await FixtureControl.configure("baseline") }
        try await FixtureControl.configure("offline-library")
        play.tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 5), "An available downloaded member must play while its server is unavailable")
        guard app.buttons["mini-pause-playback"].exists else { return }
        app.buttons["mini-player"].tap()
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
            guard let text = element as? XCUIElement, let seconds = Int(text.label.split(separator: " ").first ?? "") else { return false }
            return seconds >= 3
        }, object: app.staticTexts["playback-elapsed"])
        await fulfillment(of: [elapsed], timeout: 8)
        let requests = try await fixtureRequests().dropFirst(initialRequests)
        XCTAssertFalse(requests.contains { $0.path.hasPrefix("/api/items/\(item)/play") || $0.path.hasPrefix("/api/items/\(item)/file/") })
    }
    func testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); accountMenu(app).buttons["Change library"].tap(); app.buttons["library-podcasts"].tap()
        app.buttons["account"].tap(); app.buttons["Playlists"].tap()
        XCTAssertTrue(app.buttons["group-playlist-podcasts"].waitForExistence(timeout: 5))
        app.buttons["group-playlist-podcasts"].tap()
        XCTAssertTrue(app.buttons["group-member-podcast:episode-morning"].waitForExistence(timeout: 5))
        app.buttons["group-member-podcast:episode-morning"].tap()
        XCTAssertTrue(app.staticTexts["About this episode"].waitForExistence(timeout: 5))
        guard app.staticTexts["About this episode"].exists else { return }
        let initialRequests = try await fixtureRequests().count
        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.dropFirst(initialRequests).contains { $0.method == "POST" && $0.path == "/api/items/podcast/play/episode-morning" })
    }
    struct GroupObservation: Decodable {
        let id: String
        let name: String
        let items: [Member]?
        struct Member: Decodable { let libraryItemId: String }
    }
    struct GroupObservations: Decodable { let playlists: [GroupObservation] }
    private func observedPlaylists() async throws -> [GroupObservation] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:19765/abs/__fixture__/observations")!)
        return try JSONDecoder().decode(GroupObservations.self, from: data).playlists
    }
    func testCreateReorderRemoveAndDeletePlaylistThroughRelaunch() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["account"].tap(); app.buttons["Playlists"].tap()
        let create = app.buttons["New playlist"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        guard create.exists else { return }
        create.tap(); app.textFields["group-name"].tap(); app.textFields["group-name"].typeText("Night drive")
        app.buttons["Choose titles"].tap()
        XCTAssertTrue(app.buttons["choose-book-1"].waitForExistence(timeout: 5))
        app.buttons["choose-book-1"].tap(); app.buttons["choose-book-2"].tap(); app.buttons["Done choosing"].tap()
        app.buttons["Save group"].tap()
        let created = try await waitForPlaylist(named: "Night drive")
        XCTAssertEqual(created?.items?.map(\.libraryItemId), ["book-1", "book-2"])
        guard let created else { return }
        XCTAssertTrue(app.buttons["group-\(created.id)"].waitForExistence(timeout: 5))
        app.buttons["group-\(created.id)"].tap(); app.buttons["Edit playlist"].tap()
        app.buttons["move-up-book-2:"].tap(); app.buttons["Save group"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        app.buttons["account"].tap(); app.buttons["Playlists"].tap()
        XCTAssertTrue(app.buttons["group-\(created.id)"].waitForExistence(timeout: 5))
        app.buttons["group-\(created.id)"].tap(); app.buttons["Play playlist"].tap()
        for _ in 0..<30 {
            if try await fixtureRequests().contains(where: { $0.method == "POST" && $0.path == "/api/items/book-2/play" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let requests = try await fixtureRequests()
        XCTAssertTrue(requests.contains { $0.method == "POST" && $0.path == "/api/items/book-2/play" })
        app.buttons["Edit playlist"].tap(); app.buttons["remove-book-1:"].tap(); app.buttons["Save group"].tap()
        for _ in 0..<30 {
            if try await observedPlaylists().first(where: { $0.id == created.id })?.items?.count == 1 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let updated = try await observedPlaylists().first { $0.id == created.id }
        XCTAssertEqual(updated?.items?.map(\.libraryItemId), ["book-2"])
        app.buttons["Group actions"].tap(); app.buttons["Delete playlist"].tap()
        let deletion = app.alerts["Delete playlist?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 3))
        // The alert exists before its buttons have a frame. Tapping then makes XCTest treat the alert as an
        // interruption and dismiss it with Cancel, so wait until Delete can be tapped.
        let confirm = deletion.buttons["Delete"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: confirm)
        await fulfillment(of: [ready], timeout: 5)
        confirm.tap()
        for _ in 0..<30 {
            if try await !observedPlaylists().contains(where: { $0.id == created.id }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let remaining = try await observedPlaylists()
        XCTAssertFalse(remaining.contains { $0.id == created.id })
    }
    private func waitForPlaylist(named name: String) async throws -> GroupObservation? {
        for _ in 0..<50 {
            if let group = try await observedPlaylists().first(where: { $0.name == name }) { return group }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
    func testEstablishedCollectionAndPlaylistPlayInTheirOwnOrder() async throws {
        try await FixtureControl.configure("baseline")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        let collections = app.buttons["Collections"]
        XCTAssertTrue(collections.waitForExistence(timeout: 3))
        guard collections.exists else { return }
        collections.tap()
        XCTAssertTrue(app.buttons["group-collection-evening"].waitForExistence(timeout: 10))
        app.buttons["group-collection-evening"].tap()
        XCTAssertTrue(app.staticTexts["Stories for Tomorrow 03"].waitForExistence(timeout: 5))
        let collectionStart = try await fixtureRequests().count
        app.buttons["Play collection"].tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        var requests = try await fixtureRequests()
        XCTAssertTrue(requests.dropFirst(collectionStart).contains { $0.method == "POST" && $0.path == "/api/items/book-2/play" })
        app.buttons["Pause collection"].tap()
        XCTAssertTrue(app.buttons["mini-resume-playback"].waitForExistence(timeout: 3), "The group action must pause its currently playing member instead of restarting it")
        app.navigationBars.buttons["BackButton"].tap(); app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Playlists"].tap()
        XCTAssertTrue(app.buttons["group-playlist-evening"].waitForExistence(timeout: 10))
        app.buttons["group-playlist-evening"].tap()
        XCTAssertTrue(app.buttons["Play playlist"].waitForExistence(timeout: 5))
        let playlistStart = try await fixtureRequests().count
        app.buttons["Play playlist"].tap()
        for _ in 0..<30 {
            requests = try await fixtureRequests()
            if requests.dropFirst(playlistStart).contains(where: { $0.method == "POST" && $0.path == "/api/items/book-1/play" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(requests.dropFirst(playlistStart).contains { $0.method == "POST" && $0.path == "/api/items/book-1/play" })
        capture("Native collection and playlist playback")
    }
}
