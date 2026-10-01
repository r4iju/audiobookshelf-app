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
        /// A row created after the first was deleted; 2.30 gives it a new ID.
        func recreatedID(_ item: String, _ episode: String?) -> String { id(item, episode) + "-recreated" }
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
        /// Server 2.30 has no request barrier: a handler whose client timed out still runs to the
        /// end. The next write taken here, for `item` when given, is answered with a client timeout
        /// while its handler waits, at its first lookup, until `releaseWrite`.
        private var holdingWrite = false
        private var holdingItem: String?
        private(set) var heldWrites = 0
        private var held: [() -> Void] = []
        func holdNextWrite(item: String? = nil) { lock.lock(); holdingWrite = true; holdingItem = item; lock.unlock() }
        func takeWriteHold(items: [String]) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard holdingWrite, holdingItem.map(items.contains) ?? true else { return false }
            holdingWrite = false; heldWrites += 1
            return true
        }
        func runHeld(_ work: @escaping () -> Void) { lock.lock(); held.append(work); lock.unlock() }
        /// Lets the oldest held handler run to the end.
        func releaseWrite() {
            lock.lock(); let work = held.isEmpty ? nil : held.removeFirst(); lock.unlock()
            work?()
        }
        /// A server restart ends every held handler before it writes anything.
        func restart() { lock.lock(); held.removeAll(); lock.unlock() }
        /// Listening sessions by ID, as `local-all` leaves them: it replaces a stored session's
        /// position and total (`syncLocalSession`).
        private var sessions: [String: (time: Double, listened: Double)] = [:]
        /// Every replacement that lowered a session's total.
        private(set) var lostListening: [String] = []
        func session(_ id: String) -> (time: Double, listened: Double)? { lock.lock(); defer { lock.unlock() }; return sessions[id] }
        func listened(_ item: String) -> Double { lock.lock(); defer { lock.unlock() }; return sessionItems.filter { $0.value == item }.keys.reduce(0) { $0 + (sessions[$1]?.listened ?? 0) } }
        private var sessionItems: [String: String] = [:]
        /// 2.30's local session sync (`syncLocalSession`): the session is stored or replaced, then
        /// the progress step runs against `loaded`, the row as the request's user was loaded at its
        /// start (`getUserByIdOrOldId` with `mediaProgress`): a strictly newer row is kept, otherwise
        /// the current row is updated with no time check (`applyProgressUpdate`), or a missing one
        /// created, under a new ID when `newRowID`.
        func applySession(_ session: [String: Any], newRowID: Bool, loaded: Row?) {
            let item = session["libraryItemId"] as! String, episode = session["episodeId"] as? String
            let updated = session["updatedAt"] as! Double
            let sessionID = session["id"] as! String, listened = session["timeListening"] as! Double, time = session["currentTime"] as! Double
            lock.lock()
            if let before = sessions[sessionID], before.listened > listened { lostListening.append("\(sessionID): \(before.listened) -> \(listened)") }
            sessions[sessionID] = (time, listened); sessionItems[sessionID] = item
            lock.unlock()
            if let loaded, loaded.updatedAt > updated { return }
            let current = self[item, episode]
            let id = current?.id ?? (newRowID ? recreatedID(item, episode) : self.id(item, episode))
            self[item, episode] = Row(id: id, time: time, updatedAt: updated, ebookLocation: current?.ebookLocation)
        }
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
            let loaded = sessions.map { server[$0["libraryItemId"] as! String, $0["episodeId"] as? String] }
            if server.takeWriteHold(items: sessions.compactMap { $0["libraryItemId"] as? String }) {
                server.runHeld { zip(sessions, loaded).forEach { server.applySession($0, newRowID: true, loaded: $1) } }
                return .timedOut
            }
            zip(sessions, loaded).forEach { server.applySession($0, newRowID: false, loaded: $1) }
            return .json(200, ["results": sessions.map { ["id": $0["id"] as! String, "success": true] }])
        }
        for (item, episode) in [(book, nil), (other, nil), (podcast, "ep-1"), (podcast, "ep-2")] as [(String, String?)] {
            let path = api + "/me/progress/" + server.key(item, episode)
            harness.stub.route("GET", path) { _ in
                server.passLookup()
                guard let row = server[item, episode] else { return .status(404) }
                return .json(200, ["id": row.id, "libraryItemId": item, "episodeId": episode as Any? ?? NSNull(), "currentTime": row.time, "lastUpdate": row.updatedAt])
            }
            for id in [server.id(item, episode), server.recreatedID(item, episode)] {
                harness.stub.route("DELETE", api + "/me/progress/" + id) { _ in server.remove(id: id); return .status(200) }
            }
        }
    }

    override func tearDown() async throws {
        server.release()
        server.releaseWrite()
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
        try await harness.player.resetProgress(account: alice, itemID: item, episodeID: episode, adoption: harness.adoption)
    }

    private func deletes() -> [String] { harness.stub.requests.filter { $0.method == "DELETE" }.map(\.path) }

    /// Upserts the row as 2.30's progress PATCH does: a row recreated after a delete gets a new ID.
    private func acceptProgressPatches(_ item: String) {
        let server = server
        harness.stub.route("PATCH", api + "/me/progress/" + item) { request in
            let id = server[item, nil]?.id ?? "mp-new-" + UUID().uuidString
            server[item, nil] = Row(id: id, time: request.json?["currentTime"] as? Double ?? server[item, nil]?.time ?? 0,
                                    updatedAt: Date().timeIntervalSince1970 * 1_000, ebookLocation: request.json?["ebookLocation"] as? String)
            return .status(200)
        }
    }

    /// Answers the book's delete with `status`, after applying it when `applied`.
    private func answerDeletes(_ status: Int, applied: Bool) {
        let server = server, id = server.id(book, nil)
        harness.stub.route("DELETE", api + "/me/progress/" + id) { _ in
            if applied { server.remove(id: id) }
            return .status(status)
        }
    }

    private func patches(_ item: String) -> Int { harness.stub.requests("PATCH", api + "/me/progress/" + item).count }

    private func readPendingPage() throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: old, ebookLocation: "epubcfi(/6/4)")
        acceptProgressPatches(book)
        try harness.reading.update(account: alice, itemID: book, format: "epub", location: "epubcfi(/6/8)", fraction: 0.6, rotation: 0)
    }

    private func expectUnfinishedReset() async {
        do { _ = try await reset(book); XCTFail("The reset reported success before it finished") } catch {}
    }

    /// Publishes pending reading and waits for it to settle.
    private func publishReading() async throws {
        harness.reading.sync(api: harness.api)
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    /// Plays the download whose snapshot still holds the deleted position, and returns where it opened.
    private func startStaleDownload() async throws -> Double? {
        await harness.player.startOffline(try audio(book, serverPosition: 12, serverUpdatedAt: old))
        harness.player.pause()
        return harness.player.session == nil ? nil : harness.player.currentTime
    }

    private func assertResetFinished(file: StaticString = #filePath, line: UInt = #line) async throws {
        let primary = harness.reading.position(account: alice, itemID: book, format: "epub")
        XCTAssertEqual(primary?.location, "", "The old page survived", file: file, line: line)
        XCTAssertEqual(primary?.pending, false, file: file, line: line)
        // Reading publishes only while no audio is open.
        try await publishReading()
        XCTAssertNil(server[book, nil]?.ebookLocation.flatMap { $0.isEmpty ? nil : $0 }, "An old page restored the reset", file: file, line: line)
        let opened = try await startStaleDownload()
        XCTAssertEqual(try XCTUnwrap(opened, harness.player.error ?? "The download did not open", file: file, line: line), 0, accuracy: 0.05, file: file, line: line)
        try await settleListening()
        XCTAssertEqual(server[book, nil]?.time ?? 0, 0, accuracy: 0.05, "Old listening restored the reset", file: file, line: line)
    }

    func testARefusedLocalCleanupKeepsTheResetPendingUntilItFinishes() async throws {
        try readPendingPage()
        try harness.reading.update(account: alice, itemID: other, format: "pdf", location: "3", fraction: 0.3, rotation: 0)
        acceptProgressPatches(other)
        // The reading document can no longer be replaced.
        try? FileManager.default.removeItem(at: harness.readingFile)
        try FileManager.default.createDirectory(at: harness.readingFile.appendingPathComponent("refused"), withIntermediateDirectories: true)
        await expectUnfinishedReset()
        XCTAssertNil(server[book, nil], "Precondition: the server row was deleted")

        // Until this device's copies are discarded, none of them is published or played.
        try await publishReading()
        XCTAssertEqual(patches(book), 0, "The old page recreated the deleted progress")
        let opened = try await startStaleDownload()
        XCTAssertNil(opened, "Playback opened before the reset finished")
        XCTAssertNil(server[book, nil])

        try FileManager.default.removeItem(at: harness.readingFile)
        await harness.player.restoreListening()
        try await assertResetFinished()
        XCTAssertEqual(patches(book), 0)
        XCTAssertEqual(server[other, nil]?.ebookLocation, "3", "Unrelated reading was not published")
    }

    func testADeleteAppliedWithoutAnAnswerFinishesAfterRelaunch() async throws {
        try readPendingPage()
        answerDeletes(500, applied: true)
        await expectUnfinishedReset()
        XCTAssertNil(server[book, nil], "Precondition: the server applied the delete")

        harness.openStores()
        try await publishReading()
        XCTAssertEqual(patches(book), 0, "After a relaunch the old page recreated the deleted progress")
        answerDeletes(200, applied: true)
        await harness.player.restoreListening()
        try await assertResetFinished()
        XCTAssertEqual(patches(book), 0)
    }

    func testARejectedDeleteKeepsThisDevicesProgressUntilTheServerAcceptsIt() async throws {
        try readPendingPage()
        answerDeletes(500, applied: false)
        await expectUnfinishedReset()
        XCTAssertEqual(server[book, nil]?.time, 12, "Precondition: the server kept the progress")
        XCTAssertEqual(harness.reading.position(account: alice, itemID: book, format: "epub")?.location, "epubcfi(/6/8)", "This device's reading was discarded though the server kept the progress")

        answerDeletes(200, applied: true)
        await harness.player.restoreListening()
        XCTAssertNil(server[book, nil], "The confirmed reset was never finished")
        try await assertResetFinished()
    }

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

    func testACarriedOverPositionWaitsForAnUnfinishedResetAndIsRetiredByIt() async throws {
        harness.addProgress(book, account: AdoptionHarness.alice, position: 300, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: AdoptionHarness.legacyUpdate - 5_000)
        let server = server, book = book
        server.acceptListening = false
        harness.stub.route("PATCH", api + "/me/progress/" + book) { request in
            guard server.acceptListening else { return .status(500) }
            server[book, nil] = Row(id: "mp-new-" + UUID().uuidString, time: request.json?["currentTime"] as? Double ?? 0, updatedAt: request.json?["lastUpdate"] as? Double ?? 0)
            return .status(200)
        }
        answerDeletes(500, applied: true)
        await expectUnfinishedReset()
        server.acceptListening = true

        harness.openStores()
        _ = await harness.adoption.sync()
        XCTAssertNil(server[book, nil], "After a relaunch the carried-over position recreated the deleted progress")
        answerDeletes(200, applied: true)
        await harness.player.restoreListening()
        _ = await harness.adoption.sync()
        XCTAssertNil(server[book, nil], "The finished reset left the carried-over position to be sent")
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

    private var publications: URL { harness.base.appendingPathComponent("Native/NativeListening/publications.json") }

    private func expectRefusedReset(_ item: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await reset(item); XCTFail(message, file: file, line: line) } catch {}
    }

    func testListeningWhoseFirstSyncGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 3, updatedAt: old)
        try await open(book, at: 12)
        server.holdNextWrite()
        // A flush can join the transfer opening started; the next one sends the position.
        for _ in 0..<5 where server.heldWrites == 0 {
            await harness.player.restoreListening()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the first sync reached the server and was held")
        XCTAssertNotEqual(server[book, nil]?.time, 12, "Precondition: the held sync was not applied yet")
        try await settleListening()
        XCTAssertEqual(try XCTUnwrap(server[book, nil]).time, 12, accuracy: 0.05, "Precondition: the replay was accepted")

        var discarded = false
        do { _ = try await reset(book); discarded = true; XCTFail("The reset ran while the first sync could still be applied") } catch {}
        server.releaseWrite()
        if discarded {
            XCTAssertNil(server[book, nil], "The first sync recreated the discarded progress as \(server[book, nil]?.id ?? "")")
        } else {
            XCTAssertEqual(deletes(), [])
            XCTAssertEqual(try XCTUnwrap(server[book, nil], "The listened position was lost").time, 12, accuracy: 0.05)
        }

        // Nothing on the server shows that the held handler finished, so a relaunch keeps it refused.
        try await harness.player.stop()
        harness.openStores()
        await expectRefusedReset(book, "After a relaunch the reset ran while the first sync could still be applied")
        // Other titles are unaffected.
        server[other, nil] = Row(id: server.id(other, nil), time: 4, updatedAt: old)
        _ = try await reset(other)
        XCTAssertNil(server[other, nil])

        // Unreadable records count as unresolved.
        try Data("{not json".utf8).write(to: publications)
        harness.openStores()
        await expectRefusedReset(book, "The reset ran though the record of earlier writes could not be read")
        XCTAssertEqual(deletes(), [api + "/me/progress/" + server.id(other, nil)])

        // A restart asked for now ends every handler still running, which the owner confirms.
        try harness.player.requestServerRestart(account: alice)
        server.restart()
        try harness.player.confirmServerRestarted(account: alice)
        _ = try await reset(book)
        XCTAssertNil(server[book, nil])
    }

    func testAPrimaryPDFPageWhosePublicationGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 0, updatedAt: old, ebookLocation: "2")
        let server = server, book = book
        // 2.30's progress PATCH: updates the row, or creates one under a new ID.
        harness.stub.route("PATCH", api + "/me/progress/" + book) { request in
            let apply = {
                server[book, nil] = Row(id: server[book, nil]?.id ?? server.recreatedID(book, nil), time: server[book, nil]?.time ?? 0,
                                        updatedAt: Date().timeIntervalSince1970 * 1_000, ebookLocation: request.json?["ebookLocation"] as? String)
            }
            if server.takeWriteHold(items: [book]) { server.runHeld(apply); return .timedOut }
            apply()
            return .status(200)
        }
        try harness.reading.update(account: alice, itemID: book, format: "pdf", location: "7", fraction: 0.5, rotation: 0)
        server.holdNextWrite()
        try await publishReading()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the page reached the server and was held")
        XCTAssertEqual(server[book, nil]?.ebookLocation, "2", "Precondition: the held page was not applied yet")
        try await publishReading()
        XCTAssertEqual(harness.reading.position(account: alice, itemID: book, format: "pdf")?.pending, false, "Precondition: the replay was accepted")

        var discarded = false
        do { _ = try await reset(book); discarded = true; XCTFail("The reset ran while the first page could still be applied") } catch {}
        server.releaseWrite()
        if discarded {
            XCTAssertNil(server[book, nil], "The first page recreated the discarded progress at \(server[book, nil]?.ebookLocation ?? "")")
        } else {
            XCTAssertEqual(deletes(), [])
            XCTAssertEqual(server[book, nil]?.ebookLocation, "7")
            XCTAssertEqual(harness.reading.position(account: alice, itemID: book, format: "pdf")?.location, "7", "This device's page was discarded")
        }
    }

    func testCarriedOverListeningWhoseFirstSendGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted() async throws {
        harness.addSession("legacy-\(UUID().uuidString)", item: book, account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        harness.stub.route("GET", api + "/me/item/listening-sessions/" + book) { _ in .json(200, ["sessions": [], "numPages": 0]) }
        server[book, nil] = Row(id: server.id(book, nil), time: 12, updatedAt: old)
        server.holdNextWrite()
        _ = await harness.adoption.sync()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the carried-over session reached the server and was held")
        let replay = await harness.adoption.sync()
        XCTAssertEqual(replay.sessionsAcknowledged, 1, "Precondition: the replay was accepted")

        var discarded = false
        do { _ = try await reset(book); discarded = true; XCTFail("The reset ran while the first send could still be applied") } catch {}
        server.releaseWrite()
        if discarded {
            XCTAssertNil(server[book, nil], "The first send recreated the discarded progress at \(server[book, nil]?.time ?? 0)")
        } else {
            XCTAssertEqual(deletes(), [])
            XCTAssertNotNil(server[book, nil])
        }
    }

    private func media(_ item: String) -> ListeningMedia {
        ListeningMedia(itemID: item, episodeID: nil, title: item, author: "Synthetic", mediaType: "book", duration: 200, startTime: 0)
    }

    func testASyncThatGotNoAnswerCannotReplaceLaterListeningOfItsSession() async throws {
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-history")
        try sync.record(id: id, position: 30, listened: 30)
        server.holdNextWrite(item: book)
        do { try await sync.flush(); XCTFail("Precondition: the first sync got no answer") } catch {}
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the first sync reached the server and was held")
        try sync.record(id: id, position: 90, listened: 60)
        try? await sync.flush()
        // The held handler finishes after whatever was sent meanwhile.
        server.releaseWrite()
        XCTAssertEqual(server.lostListening, [], "The first sync replaced later listening of its session")
        XCTAssertTrue(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil) || server.session(id)?.listened == 90,
                      "Listening earned after the first sync was lost")

        // Once the owner confirms a restart the server was asked for, the rest is sent, once.
        try harness.player.requestServerRestart(account: alice)
        server.restart()
        try harness.player.confirmServerRestarted(account: alice)
        try await sync.flush()
        XCTAssertEqual(server.lostListening, [])
        XCTAssertEqual(try XCTUnwrap(server.session(id), "The session never reached the server").listened, 90, "The server does not hold the session's listening")
        XCTAssertEqual(server.listened(book), 90, "The book's listening was counted more than once")
        XCTAssertEqual(server[book, nil]?.time, 90)
        XCTAssertFalse(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil))
    }

    func testCarriedOverListeningThatGotNoAnswerCannotRewindLaterListening() async throws {
        harness.addSession("legacy-\(UUID().uuidString)", item: book, account: AdoptionHarness.alice, streamed: true, listened: 30, position: 150)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        harness.stub.route("GET", api + "/me/item/listening-sessions/" + book) { _ in .json(200, ["sessions": [], "numPages": 0]) }
        server[book, nil] = Row(id: server.id(book, nil), time: 5, updatedAt: AdoptionHarness.legacyUpdate - 60_000)
        server.holdNextWrite(item: book)
        _ = await harness.adoption.sync()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the carried-over session reached the server and was held")

        // Listening on this device after the carried-over session.
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-history")
        try sync.record(id: id, position: 12, listened: 7)
        try? await sync.flush()
        server.releaseWrite()

        try harness.player.requestServerRestart(account: alice)
        server.restart()
        try harness.player.confirmServerRestarted(account: alice)
        try await sync.flush()
        XCTAssertEqual(server[book, nil]?.time, 12, "The carried-over session rewound the position listened to after it")
        XCTAssertEqual(server.session(id)?.listened, 7)
        XCTAssertFalse(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil))
    }

    func testARestartConfirmationDoesNotSettleWritesSentAfterTheRestart() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 3, updatedAt: old)
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-restart")
        try sync.record(id: id, position: 12, listened: 12)
        server.holdNextWrite(item: book)
        try? await sync.flush()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the first sync was held")

        // The owner is asked to restart the server, and does.
        try harness.player.requestServerRestart(account: alice)
        server.restart()
        // Before the owner confirms, a background retry reaches the restarted server and gets no answer,
        server.holdNextWrite(item: book)
        try? await sync.flush()
        XCTAssertEqual(server.heldWrites, 2, "Precondition: the retry was held")
        // and a later one is answered.
        try await sync.flush()
        XCTAssertFalse(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil), "Precondition: the listening was acknowledged")
        try harness.player.confirmServerRestarted(account: alice)

        var discarded = false
        do { _ = try await reset(book); discarded = true; XCTFail("The confirmation settled a retry sent after the restart") } catch {}
        server.releaseWrite()
        if discarded {
            XCTAssertNil(server[book, nil], "The retry recreated the discarded progress as \(server[book, nil]?.id ?? "")")
        } else {
            XCTAssertEqual(deletes(), [])
            XCTAssertEqual(server[book, nil]?.time, 12)
            // Another restart, asked for after the retry, settles it.
            try harness.player.requestServerRestart(account: alice)
            server.restart()
            try harness.player.confirmServerRestarted(account: alice)
            _ = try await reset(book)
            XCTAssertNil(server[book, nil])
        }
    }

    func testListeningOfOtherTitlesIsSentWhileOneTitleWaits() async throws {
        let sync = harness.player.listening
        let waiting = try await sync.begin(media: media(book), deviceID: "device-other")
        try sync.record(id: waiting, position: 30, listened: 30)
        server.holdNextWrite(item: book)
        try? await sync.flush()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the first sync was held")
        try sync.record(id: waiting, position: 60, listened: 30)
        let unrelated = try await sync.begin(media: media(other), deviceID: "device-other")
        try sync.record(id: unrelated, position: 10, listened: 10)
        try await sync.flush()
        XCTAssertEqual(server.session(unrelated)?.listened, 10, "Another title's listening waited for this one")
        XCTAssertNil(server.session(waiting), "Later listening was sent while the first sync could still be applied")
        XCTAssertTrue(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil))
    }

    func testAnUnreadableRecordOfWritesHoldsBackNewWritesUntilARestartIsConfirmed() async throws {
        try FileManager.default.createDirectory(at: publications.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: publications)
        harness.openStores()
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-unreadable")
        try sync.record(id: id, position: 12, listened: 12)
        try await sync.flush()
        XCTAssertNil(server.session(id), "Listening was sent though earlier writes could not be read")
        XCTAssertTrue(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil))

        try harness.player.requestServerRestart(account: alice)
        try harness.player.confirmServerRestarted(account: alice)
        try await sync.flush()
        XCTAssertEqual(server.session(id)?.listened, 12)
    }

    /// The detail screen offers the restart only for `UnresolvedProgressWrites`.
    private func expectRestartAsked(_ message: String, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await reset(book); XCTFail(message, file: file, line: line) }
        catch is ApplePlayback.UnresolvedProgressWrites {}
        catch { XCTFail("\(message): \(error.localizedDescription)", file: file, line: line) }
    }

    func testAResetWithListeningHeldBackByAnUnansweredSyncAsksForARestart() async throws {
        server[book, nil] = Row(id: server.id(book, nil), time: 3, updatedAt: old)
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-held")
        try sync.record(id: id, position: 30, listened: 30)
        server.holdNextWrite(item: book)
        try? await sync.flush()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the first sync was held")
        try sync.record(id: id, position: 90, listened: 60)

        await expectRestartAsked("The reset did not ask for the restart that lets held-back listening be sent")
        XCTAssertTrue(try sync.hasLocalListening(account: alice, itemID: book, episodeID: nil, newerThan: nil), "Held-back listening was dropped")
        XCTAssertEqual(deletes(), [])

        try harness.player.requestServerRestart(account: alice)
        server.restart()
        try harness.player.confirmServerRestarted(account: alice)
        _ = try await reset(book)
        XCTAssertEqual(server.session(id)?.listened, 90, "The held-back listening was not sent before the delete")
        XCTAssertNil(server[book, nil])
    }

    func testAResetWithCarriedOverListeningHeldBackAsksForARestart() async throws {
        harness.addSession("legacy-\(UUID().uuidString)", item: book, account: AdoptionHarness.alice, streamed: true, listened: 30, position: 150)
        _ = try await harness.adoption.apply(outcome: try harness.migrate(), migrator: harness.migrator)
        harness.stub.route("GET", api + "/me/item/listening-sessions/" + book) { _ in .json(200, ["sessions": [], "numPages": 0]) }
        server[book, nil] = Row(id: server.id(book, nil), time: 3, updatedAt: old)
        let sync = harness.player.listening
        let id = try await sync.begin(media: media(book), deviceID: "device-held")
        try sync.record(id: id, position: 12, listened: 12)
        server.holdNextWrite(item: book)
        try? await sync.flush()
        XCTAssertEqual(server.heldWrites, 1, "Precondition: the sync was held")

        await expectRestartAsked("The reset did not ask for the restart that lets carried-over listening be sent")
        let waiting = await harness.adoption.sync()
        XCTAssertEqual(waiting.sessionsPending, 1, "Carried-over listening was dropped")
        XCTAssertEqual(deletes(), [])

        try harness.player.requestServerRestart(account: alice)
        server.restart()
        try harness.player.confirmServerRestarted(account: alice)
        _ = try await reset(book)
        let sent = await harness.adoption.sync()
        XCTAssertEqual(sent.sessionsPending, 0, "The carried-over listening was not sent before the delete")
        XCTAssertNil(server[book, nil])
    }
}
