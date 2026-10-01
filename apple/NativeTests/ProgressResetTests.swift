import XCTest

/// Discarding progress, against a stub that keeps progress rows the way server 2.30 does:
/// `GET /api/me/progress/:item/:episode?` returns the row, `DELETE /api/me/progress/:rowID` removes
/// it, and a local session sync replaces a row unless the row is strictly newer.
@MainActor final class ProgressResetTests: XCTestCase {
    private var harness: AdoptionHarness!
    private let api = "/abs/api"
    private let book = "li-reset-" + UUID().uuidString
    private let other = "li-other-" + UUID().uuidString
    private let podcast = "li-podcast-" + UUID().uuidString
    private let server = Rows()
    private var alice: AccountIdentity { AdoptionHarness.identity(AdoptionHarness.alice) }

    private struct Row { let id: String; var time: Double; var updatedAt: Double; var ebookLocation: String? }

    private final class Rows: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [String: Row] = [:]
        private var holding = false
        private var holdingUser = false
        private let released = DispatchSemaphore(value: 0)
        var acceptListening = true
        func key(_ item: String, _ episode: String?) -> String { episode.map { item + "/" + $0 } ?? item }
        func id(_ item: String, _ episode: String?) -> String { "mp-" + key(item, episode).replacingOccurrences(of: "/", with: "-") }
        subscript(item: String, episode: String?) -> Row? {
            get { lock.lock(); defer { lock.unlock() }; return rows[key(item, episode)] }
            set { lock.lock(); rows[key(item, episode)] = newValue; lock.unlock() }
        }
        func all() -> [(String, Row)] { lock.lock(); defer { lock.unlock() }; return rows.map { ($0.key, $0.value) } }
        func remove(id: String) { lock.lock(); rows = rows.filter { $0.value.id != id }; lock.unlock() }
        /// Holds the next row lookup until `release`, so the test can act during the reset.
        func holdNextLookup() { lock.lock(); holding = true; lock.unlock() }
        func passLookup() { lock.lock(); let wait = holding; holding = false; lock.unlock(); if wait { released.wait() } }
        func release() { released.signal() }
        private var usersBeforeHold = 0
        /// Holds a later `/api/me` request, after letting `skipping` pass, until `release`.
        func holdUser(skipping: Int = 0) { lock.lock(); holdingUser = true; usersBeforeHold = skipping; lock.unlock() }
        func passUser() {
            lock.lock()
            var wait = false
            if holdingUser { if usersBeforeHold == 0 { holdingUser = false; wait = true } else { usersBeforeHold -= 1 } }
            lock.unlock()
            if wait { released.wait() }
        }
    }

    override func setUp() async throws {
        harness = try AdoptionHarness()
        harness.signIn(AdoptionHarness.alice)
        let server = server
        harness.stub.route("GET", api + "/me") { _ in
            server.passUser()
            let progress: [[String: Any]] = server.all().map { key, row in
                let parts = key.split(separator: "/").map(String.init)
                var value: [String: Any] = ["id": row.id, "libraryItemId": parts[0], "currentTime": row.time, "duration": 20, "progress": row.time / 20, "lastUpdate": row.updatedAt]
                if parts.count > 1 { value["episodeId"] = parts[1] }
                if let location = row.ebookLocation { value["ebookLocation"] = location; value["ebookProgress"] = 0.4 }
                return value
            }
            return .json(200, StubUser.json(id: "user-1", progress: progress))
        }
        harness.stub.route("POST", api + "/session/local-all") { request in
            guard server.acceptListening else { return .status(500) }
            let sessions = request.json?["sessions"] as? [[String: Any]] ?? []
            for session in sessions {
                let item = session["libraryItemId"] as! String, episode = session["episodeId"] as? String
                let updated = session["updatedAt"] as! Double
                if let row = server[item, episode], row.updatedAt > updated { continue }
                server[item, episode] = Row(id: server.id(item, episode), time: session["currentTime"] as! Double, updatedAt: updated, ebookLocation: server[item, episode]?.ebookLocation)
            }
            return .json(200, ["results": sessions.map { ["id": $0["id"] as! String, "success": true] }])
        }
        for (item, episode) in [(book, nil), (other, nil), (podcast, "ep-1"), (podcast, "ep-2")] as [(String, String?)] {
            let path = api + "/me/progress/" + server.key(item, episode)
            harness.stub.route("GET", path) { _ in
                server.passLookup()
                guard let row = server[item, episode] else { return .status(404) }
                return .json(200, ["id": row.id, "libraryItemId": item, "episodeId": episode as Any? ?? NSNull(), "currentTime": row.time, "lastUpdate": row.updatedAt])
            }
            harness.stub.route("DELETE", api + "/me/progress/" + server.id(item, episode)) { request in
                server.remove(id: server.id(item, episode)); return .status(200)
            }
        }
    }

    override func tearDown() async throws {
        server.release()
        try? await harness.player.stop()
        harness.cleanUp()
    }

    private var old: Double { (Date().timeIntervalSince1970 - 3_600) * 1_000 }

    private func audio(_ item: String, serverPosition: Double = 0, serverUpdatedAt: Double = 0) throws -> OfflineAudio {
        let file = harness.base.appendingPathComponent(item + ".wav")
        if !FileManager.default.fileExists(atPath: file.path) { try AdoptionHarness.wav(seconds: 20, tone: 440).write(to: file) }
        let tracks = try JSONDecoder().decode([AudioTrack].self, from: Data(#"[{"contentUrl":"/audio.wav","startOffset":0,"duration":20}]"#.utf8))
        return OfflineAudio(id: item, account: alice,
                            media: ListeningMedia(itemID: item, episodeID: nil, title: item, author: "Synthetic", mediaType: "book", duration: 20, startTime: serverPosition),
                            files: [file], tracks: tracks, chapters: [], serverPosition: serverPosition, serverUpdatedAt: serverUpdatedAt)
    }

    /// Opens downloaded audio paused at `position`, recording it in the listening journal.
    private func open(_ item: String, at position: Double) async throws {
        await harness.player.startOffline(try audio(item))
        harness.player.pause()
        XCTAssertNotNil(harness.player.session, harness.player.error ?? "No playback session")
        try await harness.player.seek(to: position, autoplay: false)
    }

    /// A flush joining a transfer already past its sending loop does not send later listening.
    private func settleListening() async throws {
        await harness.player.restoreListening()
        try await Task.sleep(nanoseconds: 200_000_000)
        await harness.player.restoreListening()
    }

    private func index(_ method: String, _ path: String) -> Int? {
        harness.stub.requests.lastIndex { $0.method == method && $0.path == path }
    }

    private func reset(_ item: String, episode: String? = nil) async throws -> CurrentUser {
        try await harness.player.resetProgress(account: alice, itemID: item, episodeID: episode, reading: harness.reading, adoption: harness.adoption)
    }

    private func deletes() -> [String] { harness.stub.requests.filter { $0.method == "DELETE" }.map(\.path) }

    func testResettingABookDeletesItsServerRowAndReturnsTheUserWithoutIt() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: old)
        server[other, nil] = Row(id: server.id(other, nil), time: 4, updatedAt: old)
        let user = try await reset(book)
        XCTAssertEqual(deletes(), [api + "/me/progress/" + server.id(book, nil)])
        XCTAssertNil(user.mediaProgress.first { $0.libraryItemId == book })
        XCTAssertNotNil(user.mediaProgress.first { $0.libraryItemId == other })
    }

    func testResettingAnEpisodeDeletesOnlyThatEpisodesRow() async throws {
        server[podcast, "ep-1"] = Row(id: server.id(podcast, "ep-1"), time: 12, updatedAt: old)
        server[podcast, "ep-2"] = Row(id: server.id(podcast, "ep-2"), time: 6, updatedAt: old)
        let user = try await reset(podcast, episode: "ep-1")
        XCTAssertEqual(deletes(), [api + "/me/progress/" + server.id(podcast, "ep-1")])
        XCTAssertNil(user.mediaProgress.first { $0.libraryItemId == podcast && $0.episodeId == "ep-1" })
        XCTAssertNotNil(user.mediaProgress.first { $0.libraryItemId == podcast && $0.episodeId == "ep-2" })
    }

    func testOpenMediaIsClosedAndItsOldPositionDoesNotReturnOnTheNextStart() async throws {
        try await open(book, at: 12)
        try await settleListening()
        XCTAssertEqual(try XCTUnwrap(server[book, nil]).time, 12, accuracy: 0.05)
        _ = try await reset(book)
        XCTAssertNil(harness.player.session)
        XCTAssertNil(server[book, nil], "The reset was restored or never sent")

        // A download snapshot still remembers the old server position.
        let snapshot = try audio(book, serverPosition: 12, serverUpdatedAt: old)
        XCTAssertFalse(try harness.player.hasFinishedOffline(snapshot, serverFinished: false))
        await harness.player.startOffline(snapshot)
        harness.player.pause()
        XCTAssertEqual(harness.player.currentTime, 0, accuracy: 0.05)
    }

    func testPendingListeningIsPublishedBeforeTheDeleteAndUnrelatedQueuedListeningSurvives() async throws {
        server.acceptListening = false
        try await open(book, at: 12)
        try await open(other, at: 7)
        try await settleListening()
        XCTAssertNil(server[book, nil]); XCTAssertNil(server[other, nil])
        server.acceptListening = true

        _ = try await reset(book)
        let deleted = try XCTUnwrap(index("DELETE", api + "/me/progress/" + server.id(book, nil)), "The reset never deleted the row")
        let published = try XCTUnwrap(index("POST", api + "/session/local-all"))
        XCTAssertLessThan(published, deleted, "Pending listening was sent after the delete and restored the progress")
        XCTAssertNil(server[book, nil])
        XCTAssertEqual(try XCTUnwrap(server[other, nil], "Unrelated queued listening was lost").time, 7, accuracy: 0.05)
        XCTAssertEqual(harness.player.itemID, other, "Unrelated open media was closed")
    }

    func testUnpublishableListeningLeavesEverythingInPlace() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 3, updatedAt: old)
        server.acceptListening = false
        try await open(book, at: 12)
        try await settleListening()
        do {
            _ = try await reset(book)
            XCTFail("The reset ignored unsent listening")
        } catch {}
        XCTAssertEqual(deletes(), [])
        server.acceptListening = true
        try await settleListening()
        XCTAssertEqual(try XCTUnwrap(server[book, nil]).time, 12, accuracy: 0.05, "Queued listening was lost")
    }

    // Requests in flight are already cancelled by a sign-in change; this one happens while the reset
    // waits for a reading publication, before its own requests start.
    func testASignInChangeDuringTheResetNeverDeletesForTheReturningAccount() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: old)
        try harness.reading.update(account: alice, itemID: other, format: "pdf", location: "3", fraction: 0.3, rotation: 0)
        let users = harness.stub.requests("GET", api + "/me").count
        // The store's own lookup passes; the publication's listening flush is held.
        server.holdUser(skipping: 1)
        harness.reading.sync(api: harness.api)
        for _ in 0..<200 where harness.stub.requests("GET", api + "/me").count < users + 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(harness.stub.requests("GET", api + "/me").count, users + 2, "The reading publication never started")
        let resetting = Task { try await reset(book) }
        try await Task.sleep(nanoseconds: 100_000_000)
        harness.signIn(AdoptionHarness.bob)
        harness.signIn(AdoptionHarness.alice)
        server.release()
        do { _ = try await resetting.value; XCTFail("The reset survived a sign-in change") } catch {}
        XCTAssertEqual(deletes(), [])
        XCTAssertNotNil(server[book, nil])
    }

    func testReadingIsResetAndNeitherPendingPagesNorOlderSnapshotsRestoreIt() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 0, updatedAt: old, ebookLocation: "epubcfi(/6/4)")
        try harness.reading.update(account: alice, itemID: book, format: "epub", location: "epubcfi(/6/8)", fraction: 0.6, rotation: 0)
        try harness.reading.update(account: alice, itemID: book, format: "pdf", location: "9", fraction: 0.5, rotation: 90, fileID: "companion")
        _ = try await reset(book)

        let snapshot = try JSONDecoder().decode(MediaProgress.self, from: JSONSerialization.data(withJSONObject: ["libraryItemId": book, "ebookLocation": "epubcfi(/6/4)", "ebookProgress": 0.4, "lastUpdate": old]))
        try harness.reading.adopt(snapshot, account: alice, itemID: book, format: "epub")
        let primary = harness.reading.position(account: alice, itemID: book, format: "epub")
        XCTAssertTrue(primary == nil || (primary?.location == "" && primary?.pending == false), "Reading resumes at \(primary?.location ?? "")")
        XCTAssertEqual(harness.reading.position(account: alice, itemID: book, format: "pdf", fileID: "companion")?.location, "9", "A supplementary document's own location was discarded")

        harness.reading.sync(api: harness.api)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(harness.stub.requests("PATCH", api + "/me/progress/" + book).count, 0, "An old page was published after the reset")
        XCTAssertNil(server[book, nil])
    }

    // The legacy position is newer than the server's, and could not be sent during the reset.
    func testACarriedOverLegacyPositionIsRetiredInsteadOfRestoringTheReset() async throws {
        harness.addProgress(book, account: AdoptionHarness.alice, position: 300, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: AdoptionHarness.legacyUpdate - 5_000)
        let server = server, book = book
        server.acceptListening = false
        harness.stub.route("PATCH", api + "/me/progress/" + book) { request in
            guard server.acceptListening else { return .status(500) }
            server[book, nil] = Row(id: server.id(book, nil), time: request.json?["currentTime"] as? Double ?? 0, updatedAt: request.json?["lastUpdate"] as? Double ?? 0)
            return .status(200)
        }
        _ = try await reset(book)
        server.acceptListening = true
        _ = await harness.adoption.sync()
        let deleted = try XCTUnwrap(index("DELETE", api + "/me/progress/" + server.id(book, nil)))
        XCTAssertFalse(harness.stub.requests.enumerated().contains { $0.offset > deleted && $0.element.method == "PATCH" }, "The carried-over position was sent after the reset")
        XCTAssertNil(server[book, nil])
    }

    func testCarriedOverLegacyListeningIsDeliveredBeforeTheDeleteAndCannotRestoreIt() async throws {
        harness.addSession("legacy-\(UUID().uuidString)", item: book, account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        harness.stub.route("GET", api + "/me/item/listening-sessions/" + book) { _ in .json(200, ["sessions": [], "numPages": 0]) }
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: old)
        _ = try await reset(book)
        _ = await harness.adoption.sync()
        XCTAssertNil(server[book, nil], "Carried-over listening restored the reset")
        let deleted = try XCTUnwrap(index("DELETE", api + "/me/progress/" + server.id(book, nil)))
        let delivered = harness.stub.requests.enumerated().contains { offset, request in
            offset < deleted && request.path == api + "/session/local-all"
                && ((request.json?["sessions"] as? [[String: Any]])?.first?["timeListening"] as? Double) == 30
        }
        XCTAssertTrue(delivered, "Carried-over listening was not delivered before the delete")
    }

    func testPlaybackStartedDuringTheResetBeginsFromTheStart() async throws {
        try await open(book, at: 12)
        try await settleListening()
        try await harness.player.stop()
        server.holdNextLookup()
        let resetting = Task { try await reset(book) }
        for _ in 0..<200 where index("GET", api + "/me/progress/" + book) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let snapshot = try audio(book, serverPosition: 12, serverUpdatedAt: old)
        let start = Task { await harness.player.startOffline(snapshot) }
        try await Task.sleep(nanoseconds: 100_000_000)
        server.release()
        _ = try await resetting.value
        await start.value
        harness.player.pause()
        XCTAssertEqual(harness.player.currentTime, 0, accuracy: 0.05)
        try await settleListening()
        XCTAssertEqual(server[book, nil]?.time ?? 0, 0, accuracy: 0.05, "Old listening restored the reset")
    }
}
