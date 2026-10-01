import PDFKit
import XCTest

/// Unsent legacy listening and unfinished downloads, against a stub with the request and response
/// shapes of the Audiobookshelf 2.30 server.
@MainActor final class AdoptionSyncTests: XCTestCase {
    private var h: AdoptionHarness!
    private let api = "/abs/api"

    override func setUp() async throws { h = try AdoptionHarness() }
    override func tearDown() async throws { h.cleanUp() }

    private func serveUser(_ id: String = "user-1", progress: [[String: Any]] = []) {
        h.stub.route("GET", api + "/me") { _ in .json(200, StubUser.json(id: id, progress: progress)) }
        for value in progress {
            let path = api + "/me/progress/" + (value["libraryItemId"] as? String ?? "") + ((value["episodeId"] as? String).map { "/" + $0 } ?? "")
            h.stub.route("GET", path) { _ in .json(200, value) }
        }
    }

    private func sentSessions() -> [[String: Any]] {
        h.stub.requests("POST", api + "/session/local-all").compactMap { ($0.json?["sessions"] as? [[String: Any]])?.first }
    }

    func testADownloadedSessionIsAcknowledgedOnlyAfterTheServerAcceptedExactlyIt() async throws {
        try h.addAudiobook("li-audio", seconds: [1], position: 0.5)
        h.addSession("s-local", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 120, position: 0.5)
        h.addSession("s-bob", item: "li-audio", account: AdoptionHarness.bob, streamed: false, listened: 40, position: 0.2)
        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        XCTAssertEqual(report.listening.first { $0.account == AdoptionHarness.alice }?.pendingSessions, 1)
        XCTAssertTrue(report.summary.contains("listening"), report.summary)

        h.signIn(AdoptionHarness.alice)
        serveUser()
        var answers: [StubServer.Response] = [
            .status(500),
            .json(200, ["results": [["id": "s-local", "success": false, "error": "Media item not found"]]]),
            .json(200, ["results": [["id": "other", "success": true]]]),
            .json(200, ["results": [["id": "s-local", "success": true, "progressSynced": true]]]),
        ]
        h.stub.route("POST", api + "/session/local-all") { _ in answers.isEmpty ? .status(500) : answers.removeFirst() }

        var acknowledged: [Int] = []
        for _ in 0..<4 {
            h.openStores()
            let sync = await h.adoption.sync()
            XCTAssertEqual(sync.account, AdoptionHarness.alice)
            acknowledged.append(sync.sessionsAcknowledged)
            if sync.sessionsAcknowledged == 0 { XCTAssertEqual(sync.sessionsPending, 1); XCTAssertFalse(sync.failures.isEmpty) }
        }
        XCTAssertEqual(acknowledged, [0, 0, 0, 1])
        let finalSync = await h.adoption.sync()
        XCTAssertEqual(finalSync.sessionsPending, 0)

        let sent = sentSessions()
        XCTAssertEqual(sent.count, 4, "acknowledged sessions are not sent again; Bob's waits for Bob")
        for session in sent {
            XCTAssertEqual(session["id"] as? String, "s-local")
            XCTAssertEqual(session["userId"] as? String, "user-1")
            XCTAssertEqual(session["libraryItemId"] as? String, "li-audio")
            XCTAssertEqual(session["timeListening"] as? Double, 120, "a downloaded session carries its whole total")
            XCTAssertEqual(session["currentTime"] as? Double, 0.5)
            XCTAssertEqual(session["updatedAt"] as? Double, AdoptionHarness.legacyUpdate)
        }

        h.signIn(AdoptionHarness.bob)
        serveUser("user-2")
        answers = [.json(200, ["results": [["id": "s-bob", "success": true]]])]
        let bob = await h.adoption.sync()
        XCTAssertEqual(bob.sessionsAcknowledged, 1)
        XCTAssertEqual(sentSessions().last?["userId"] as? String, "user-2")
        XCTAssertEqual(sentSessions().last?["timeListening"] as? Double, 40)
    }

    func testAStreamedSessionStillOpenOnTheServerGetsItsUnsentListeningAddedAtMostOnce() async throws {
        h.addSession("s-open", item: "li-stream", account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        h.addSession("s-answered", item: "li-other", account: AdoptionHarness.alice, streamed: true, listened: 20, position: 100)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        // The server's progress moved on after the legacy app's last report.
        serveUser(progress: [["libraryItemId": "li-stream", "currentTime": 500, "duration": 900, "progress": 0.55, "isFinished": false, "lastUpdate": AdoptionHarness.legacyUpdate + 60_000]])
        h.stub.route("GET", api + "/me/progress/li-other") { _ in .status(404) }
        var total = 100.0
        h.stub.route("GET", api + "/session/s-open") { _ in .json(200, ["id": "s-open", "userId": "user-1", "libraryItemId": "li-stream", "timeListening": total, "currentTime": 500, "duration": 900]) }
        h.stub.route("GET", api + "/session/s-answered") { _ in .json(200, ["id": "s-answered", "userId": "user-1", "libraryItemId": "li-other", "timeListening": 0, "currentTime": 0, "duration": 900]) }
        h.stub.route("POST", api + "/session/s-open/sync") { request in
            total += (request.json?["timeListened"] as? Double) ?? 0
            return .lost
        }
        h.stub.route("POST", api + "/session/s-answered/sync") { _ in .status(200) }

        let first = await h.adoption.sync()
        h.openStores()
        let second = await h.adoption.sync()
        let third = await h.adoption.sync()

        XCTAssertEqual(first.sessionsAcknowledged, 1, "an answered addition is acknowledged")
        XCTAssertEqual(second.sessionsAcknowledged + third.sessionsAcknowledged, 0, "a grown total does not prove which listening it holds")
        XCTAssertEqual(third.sessionsUnconfirmed, 1)
        XCTAssertEqual(third.sessionsPending, 0)
        XCTAssertEqual(total, 130, "the unsent 30 s are never added a second time")
        let reports = h.stub.requests("POST", api + "/session/s-open/sync")
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.json?["timeListened"] as? Double, 30)
        XCTAssertEqual(reports.first?.json?["currentTime"] as? Double, 500, "an older legacy position does not rewind the server")
        XCTAssertTrue(sentSessions().isEmpty, "a delta is never sent where the server replaces the total")

        let applied = try await h.adoption.apply(outcome: try XCTUnwrap(h.migrator.committedOutcome()), migrator: h.migrator)
        XCTAssertEqual(applied.listening.first { $0.account == AdoptionHarness.alice }?.unconfirmedSessions, 1)
        XCTAssertTrue(applied.issues.contains { $0.contains("could not be confirmed") }, "\(applied.issues)")
    }

    func testAStreamedSessionTheServerClosedIsSentAsItsStoredTotalPlusTheUnsentListening() async throws {
        h.addSession("s-closed", item: "li-stream", account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        h.stub.route("GET", api + "/session/s-closed") { _ in .status(404) }
        h.stub.route("GET", api + "/me/item/listening-sessions/li-stream") { request in
            let page = Int(request.query["page"] ?? "0") ?? 0
            let sessions: [[String: Any]] = page == 0
                ? [["id": "s-other", "libraryItemId": "li-stream", "timeListening": 999]]
                : [["id": "s-closed", "libraryItemId": "li-stream", "timeListening": 200]]
            return .json(200, ["total": 2, "numPages": 2, "page": page, "itemsPerPage": 1, "sessions": sessions])
        }
        var answers: [StubServer.Response] = [.status(500), .lost, .json(200, ["results": [["id": "s-closed", "success": true]]])]
        h.stub.route("POST", api + "/session/local-all") { _ in answers.isEmpty ? .status(500) : answers.removeFirst() }

        for _ in 0..<3 {
            h.openStores()
            _ = await h.adoption.sync()
        }
        let done = await h.adoption.sync()

        XCTAssertEqual(done.sessionsPending, 0)
        let sent = sentSessions()
        XCTAssertEqual(sent.count, 3)
        for session in sent {
            XCTAssertEqual(session["id"] as? String, "s-closed")
            XCTAssertEqual(session["timeListening"] as? Double, 230, "the same total on every retry, never the bare delta")
            XCTAssertEqual(session["currentTime"] as? Double, 400)
            XCTAssertEqual(session["updatedAt"] as? Double, AdoptionHarness.legacyUpdate)
        }
        XCTAssertTrue(h.stub.requests("POST", api + "/session/s-closed/sync").isEmpty)
        XCTAssertEqual(h.stub.requests("GET", api + "/me/item/listening-sessions/li-stream").count, 6, "the stored total is read again before every attempt")
    }

    func testAStreamedSessionTheServerClosedIsNotOverwrittenOnceSomethingElseChangedIt() async throws {
        h.addSession("s-closed", item: "li-stream", account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        h.stub.route("GET", api + "/session/s-closed") { _ in .status(404) }
        var stored = 200.0
        h.stub.route("GET", api + "/me/item/listening-sessions/li-stream") { request in
            .json(200, ["total": 1, "numPages": 1, "page": 0, "itemsPerPage": 50, "sessions": [["id": "s-closed", "libraryItemId": "li-stream", "timeListening": stored]]])
        }
        h.stub.route("POST", api + "/session/local-all") { request in
            stored = ((request.json?["sessions"] as? [[String: Any]])?.first?["timeListening"] as? Double) ?? stored
            // The answer is lost, and another device then writes the same session.
            stored += 30
            return .lost
        }

        let first = await h.adoption.sync()
        h.openStores()
        let second = await h.adoption.sync()
        let third = await h.adoption.sync()

        XCTAssertEqual(sentSessions().count, 1, "a total someone else changed is not replaced")
        XCTAssertEqual(stored, 260)
        XCTAssertEqual(first.sessionsAcknowledged + second.sessionsAcknowledged + third.sessionsAcknowledged, 0)
        XCTAssertEqual(third.sessionsUnconfirmed, 1)
        XCTAssertEqual(third.sessionsPending, 0)
    }

    func testOnlyLegacyPositionsNewerThanTheServersAreSent() async throws {
        h.addProgress("li-newer", account: AdoptionHarness.alice, position: 300, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        h.addProgress("li-older", account: AdoptionHarness.alice, position: 100, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        h.addProgress("li-reopened", account: AdoptionHarness.alice, position: 50, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        h.addProgress("li-bob", account: AdoptionHarness.bob, position: 70, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        XCTAssertEqual(report.listening.first { $0.account == AdoptionHarness.alice }?.pendingProgress, 3)
        h.signIn(AdoptionHarness.alice)
        serveUser(progress: [
            ["libraryItemId": "li-newer", "currentTime": 10, "duration": 900, "progress": 0.01, "isFinished": false, "lastUpdate": AdoptionHarness.legacyUpdate - 5_000],
            ["libraryItemId": "li-older", "currentTime": 700, "duration": 900, "progress": 0.77, "isFinished": false, "lastUpdate": AdoptionHarness.legacyUpdate + 5_000],
            ["libraryItemId": "li-reopened", "currentTime": 900, "duration": 900, "progress": 1, "isFinished": true, "lastUpdate": AdoptionHarness.legacyUpdate - 5_000],
        ])
        for item in ["li-newer", "li-older", "li-reopened", "li-bob"] {
            h.stub.route("PATCH", api + "/me/progress/" + item) { _ in .status(200) }
        }

        let sync = await h.adoption.sync()
        _ = await h.adoption.sync()

        XCTAssertEqual(sync.progressSent, 2)
        XCTAssertEqual(sync.progressPending, 0)
        let newer = h.stub.requests("PATCH", api + "/me/progress/li-newer")
        XCTAssertEqual(newer.count, 1)
        XCTAssertEqual(newer.first?.json?["currentTime"] as? Double, 300)
        XCTAssertEqual(newer.first?.json?["duration"] as? Double, 900)
        XCTAssertEqual(newer.first?.json?["isFinished"] as? Bool, false)
        XCTAssertEqual(newer.first?.json?["lastUpdate"] as? Double, AdoptionHarness.legacyUpdate)
        XCTAssertTrue(h.stub.requests("PATCH", api + "/me/progress/li-older").isEmpty)
        XCTAssertTrue(h.stub.requests("PATCH", api + "/me/progress/li-bob").isEmpty)
        // The server keeps a finished item finished unless told otherwise first.
        let reopened = h.stub.requests("PATCH", api + "/me/progress/li-reopened")
        XCTAssertEqual(reopened.count, 2)
        XCTAssertEqual(reopened.first?.json?.keys.sorted(), ["isFinished", "lastUpdate"])
        XCTAssertLessThan(try XCTUnwrap(reopened.first?.json?["lastUpdate"] as? Double), AdoptionHarness.legacyUpdate, "the reset never looks newer than the legacy row")
        XCTAssertEqual(reopened.last?.json?["currentTime"] as? Double, 50)
    }

    func testAnUnfinishedDownloadAndASupplementaryPDFAreCompletedFromTheServersItem() async throws {
        try h.addInterruptedDownload("li-int", finished: [("01.wav", 1)], unfinished: ["02.wav"])
        try h.addAudiobook("li-sup", seconds: [1], supplementary: AdoptionHarness.pdf(pages: 5))
        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-int" }?.status, .waitingForServer)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-sup" && $0.supplementaryFile == "companion.pdf" }?.status, .waitingForServer)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-sup" && $0.supplementaryFile == nil }?.status, .ready)

        h.signIn(AdoptionHarness.alice)
        serveUser()
        func track(_ item: String, _ ino: String, _ name: String, _ offset: Double) -> [String: Any] {
            ["contentUrl": "/api/items/\(item)/file/\(ino)", "mimeType": "audio/wav", "metadata": ["filename": name, "ext": ".wav"], "startOffset": offset, "duration": 1]
        }
        h.stub.route("GET", api + "/items/li-int") { _ in
            .json(200, ["id": "li-int", "mediaType": "book",
                        "media": ["metadata": ["title": "Server title"], "duration": 2, "tracks": [track("li-int", "ino-a", "01.wav", 0), track("li-int", "ino-b", "02.wav", 1)],
                                  "chapters": [["id": 0, "start": 0, "end": 2, "title": "One"]]],
                        "libraryFiles": [["ino": "ino-a", "fileType": "audio", "metadata": ["filename": "01.wav", "ext": ".wav"]],
                                         ["ino": "ino-b", "fileType": "audio", "metadata": ["filename": "02.wav", "ext": ".wav"]]]])
        }
        h.stub.route("GET", api + "/items/li-sup") { _ in
            .json(200, ["id": "li-sup", "mediaType": "book",
                        "media": ["metadata": ["title": "Title li-sup"], "duration": 1, "tracks": [track("li-sup", "ino-li-sup-1", "01 Part.wav", 0)]],
                        "libraryFiles": [["ino": "ino-li-sup-1", "fileType": "audio", "metadata": ["filename": "01 Part.wav", "ext": ".wav"]],
                                         ["ino": "ino-companion", "fileType": "ebook", "metadata": ["filename": "companion.pdf", "ext": ".pdf"]]]])
        }

        _ = await h.adoption.sync()
        h.openStores()
        _ = await h.adoption.sync()

        let interrupted = try XCTUnwrap(h.entry("li-int"))
        XCTAssertEqual(interrupted.state, .failed, "one part still has to be downloaded")
        XCTAssertEqual(interrupted.finished, [0])
        XCTAssertEqual(interrupted.tracks.map(\.contentUrl), ["/api/items/li-int/file/ino-a", "/api/items/li-int/file/ino-b"])
        XCTAssertEqual(interrupted.chapters.map(\.title), ["One"])
        let kept = h.downloadsDirectory.appendingPathComponent(interrupted.id).appendingPathComponent("audio-0.wav")
        XCTAssertEqual(try Data(contentsOf: kept), try h.legacyBytes("li-int/01.wav"))

        let supplementary = try XCTUnwrap(h.entry("li-sup", supplementary: "ino-companion"))
        XCTAssertEqual(supplementary.state, .ready)
        XCTAssertTrue(supplementary.tracks.isEmpty)
        let file = try h.downloads.ebookURL(supplementary)
        XCTAssertEqual(try Data(contentsOf: file), try h.legacyBytes("li-sup/companion.pdf"))
        XCTAssertEqual(PDFDocument(url: file)?.pageCount, 5)

        XCTAssertEqual(h.stub.requests("GET", api + "/items/li-int").count, 1, "a completed item is not fetched again")
        XCTAssertEqual(h.stub.requests("GET", api + "/items/li-sup").count, 1)
        let applied = try await h.adoption.apply(outcome: try XCTUnwrap(h.migrator.committedOutcome()), migrator: h.migrator)
        XCTAssertEqual(applied.downloads.first { $0.libraryItemID == "li-sup" && $0.supplementaryFile == "companion.pdf" }?.status, .ready)
        XCTAssertEqual(applied.downloads.first { $0.libraryItemID == "li-int" }?.status, .partial)
    }

    func testAStreamedSessionTheServerClosedKeepsLaterPositionsAndTimesOfItsRow() async throws {
        let legacy = AdoptionHarness.legacyUpdate
        h.addSession("s-retried", item: "li-stream", account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        h.addSession("s-later", item: "li-later", account: AdoptionHarness.alice, streamed: true, listened: 30, position: 400)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        h.stub.route("GET", api + "/session/s-retried") { _ in .status(404) }
        h.stub.route("GET", api + "/session/s-later") { _ in .status(404) }
        var rows: [String: [String: Any]] = [
            "s-retried": ["id": "s-retried", "libraryItemId": "li-stream", "timeListening": 200, "currentTime": 380, "updatedAt": legacy - 60_000],
            // Already written after the legacy app's last update.
            "s-later": ["id": "s-later", "libraryItemId": "li-later", "timeListening": 200, "currentTime": 600.0, "updatedAt": legacy + 60_000],
        ]
        for (id, item) in [("s-retried", "li-stream"), ("s-later", "li-later")] {
            h.stub.route("GET", api + "/me/item/listening-sessions/" + item) { _ in .json(200, ["total": 1, "numPages": 1, "page": 0, "itemsPerPage": 50, "sessions": [rows[id]!]]) }
        }
        h.stub.route("POST", api + "/session/local-all") { request in
            let sent = (request.json?["sessions"] as? [[String: Any]])?.first ?? [:]
            let id = sent["id"] as? String ?? ""
            rows[id]?["timeListening"] = sent["timeListening"]
            rows[id]?["currentTime"] = sent["currentTime"]
            rows[id]?["updatedAt"] = sent["updatedAt"]
            // The answer is lost; another device then moves the same row on, with the same total.
            rows[id]?["currentTime"] = 700.0
            rows[id]?["updatedAt"] = legacy + 120_000
            return .lost
        }

        _ = await h.adoption.sync()
        h.openStores()
        let second = await h.adoption.sync()

        XCTAssertEqual(sentSessions().map { $0["id"] as? String }, ["s-retried"], "a row written later is never replaced, on the first attempt or a retry")
        XCTAssertEqual(rows["s-retried"]?["currentTime"] as? Double, 700)
        XCTAssertEqual(rows["s-later"]?["currentTime"] as? Double, 600)
        XCTAssertEqual(second.sessionsUnconfirmed, 2)
        XCTAssertEqual(second.sessionsPending, 0)
    }

    func testAStagedDownloadIsPlacedOffTheMainActor() async throws {
        try h.addAudiobook("li-sup", seconds: [1], supplementary: AdoptionHarness.pdf(pages: 5))
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        h.stub.route("GET", api + "/items/li-sup") { _ in
            .json(200, ["id": "li-sup", "mediaType": "book",
                        "media": ["metadata": ["title": "Title li-sup"], "duration": 1,
                                  "tracks": [["contentUrl": "/api/items/li-sup/file/ino-li-sup-1", "mimeType": "audio/wav", "metadata": ["filename": "01 Part.wav", "ext": ".wav"], "startOffset": 0, "duration": 1]]],
                        "libraryFiles": [["ino": "ino-li-sup-1", "fileType": "audio", "metadata": ["filename": "01 Part.wav", "ext": ".wav"]],
                                         ["ino": "ino-companion", "fileType": "ebook", "metadata": ["filename": "companion.pdf", "ext": ".pdf"]]]])
        }
        let lock = NSLock()
        var onMain: [Bool] = []
        h.adoption.beforePlacing = { _ in lock.lock(); onMain.append(Thread.isMainThread); lock.unlock() }

        let report = await h.adoption.sync()

        XCTAssertEqual(report.downloadsCompleted, 1)
        XCTAssertEqual(onMain, [false], "the staged file is read and placed off the main actor")
        let entry = try XCTUnwrap(h.entry("li-sup", supplementary: "ino-companion"))
        XCTAssertEqual(try Data(contentsOf: try h.downloads.ebookURL(entry)), try h.legacyBytes("li-sup/companion.pdf"))
    }

    private func accepting() -> (StubServer.Request) -> StubServer.Response {
        { request in
            let id = ((request.json?["sessions"] as? [[String: Any]])?.first?["id"] as? String) ?? ""
            return .json(200, ["results": [["id": id, "success": true]]])
        }
    }

    func testADownloadedSessionTheLegacyAppAlreadyPostedUpdatesThatServerRow() async throws {
        h.addSession("play_local_posted", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 120, position: 0.5)
        h.addSession("play_local_new", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 40, position: 0.7, updatedAt: AdoptionHarness.legacyUpdate + 10_000_000)
        h.addSession("play_local_twice", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 15, position: 0.9, updatedAt: AdoptionHarness.legacyUpdate + 20_000_000)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        // The server stored the legacy app's earlier post of the first session under a new id.
        let posted = AdoptionHarness.legacyUpdate - 600_000
        h.stub.route("GET", api + "/me/item/listening-sessions/li-audio") { request in
            let page = Int(request.query["page"] ?? "0") ?? 0
            let sessions: [[String: Any]] = page == 0
                ? [["id": "unrelated", "libraryItemId": "li-audio", "startedAt": posted - 5_000_000, "timeListening": 5],
                   ["id": "twice-a", "libraryItemId": "li-audio", "startedAt": posted + 20_000_000, "timeListening": 7]]
                : [["id": "server-row", "libraryItemId": "li-audio", "startedAt": posted, "timeListening": 80],
                   ["id": "twice-b", "libraryItemId": "li-audio", "startedAt": posted + 20_000_000, "timeListening": 9]]
            return .json(200, ["total": 4, "numPages": 2, "page": page, "itemsPerPage": 2, "sessions": sessions])
        }
        h.stub.route("POST", api + "/session/local-all", accepting())

        let report = await h.adoption.sync()
        let again = await h.adoption.sync()

        XCTAssertEqual(report.sessionsAcknowledged, 2)
        XCTAssertEqual(again.sessionsPending, 1, "a session matching two server rows is kept rather than guessed")
        XCTAssertFalse(again.failures.isEmpty)
        let sent = Dictionary(uniqueKeysWithValues: sentSessions().map { (($0["timeListening"] as? Double) ?? 0, ($0["id"] as? String) ?? "") })
        XCTAssertEqual(sentSessions().count, 2)
        XCTAssertEqual(sent[120], "server-row", "the whole total replaces the row the legacy app created")
        let fresh = try XCTUnwrap(sent[40])
        XCTAssertNotNil(UUID(uuidString: fresh), "a session the server never had gets a stable id of its own")
        XCTAssertFalse(fresh.hasPrefix("play_local_"))
    }

    func testAPostedSessionTheServerHoldsWithMoreOrNewerListeningIsNotReplaced() async throws {
        let start = AdoptionHarness.legacyUpdate
        h.addSession("play_local_more", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 120, position: 0.5, updatedAt: start)
        h.addSession("play_local_newer", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 45, position: 0.6, updatedAt: start + 10_000_000)
        h.addSession("play_local_same", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 60, position: 0.7, updatedAt: start + 20_000_000)
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        serveUser()
        // The rows 2.30 stored for the legacy app's earlier posts, under ids of its own.
        h.stub.route("GET", api + "/me/item/listening-sessions/li-audio") { _ in
            .json(200, ["total": 3, "numPages": 1, "page": 0, "itemsPerPage": 50, "sessions": [
                ["id": "row-more", "libraryItemId": "li-audio", "startedAt": start - 600_000, "updatedAt": start, "timeListening": 150, "currentTime": 0.5],
                ["id": "row-newer", "libraryItemId": "li-audio", "startedAt": start + 10_000_000 - 600_000, "updatedAt": start + 10_000_000 + 60_000, "timeListening": 30, "currentTime": 0.9],
                ["id": "row-same", "libraryItemId": "li-audio", "startedAt": start + 20_000_000 - 600_000, "updatedAt": start + 20_000_000, "timeListening": 60, "currentTime": 0.7],
            ]])
        }
        h.stub.route("POST", api + "/session/local-all", accepting())

        let report = await h.adoption.sync()
        let again = await h.adoption.sync()

        XCTAssertTrue(sentSessions().isEmpty, "a row with more, newer or the same listening is never replaced")
        XCTAssertEqual(report.sessionsAcknowledged, 1, "only the row holding exactly this session acknowledges it")
        XCTAssertEqual(again.sessionsUnconfirmed, 2, "the others are kept and reported, not claimed as sent")
        XCTAssertEqual(again.sessionsPending, 0)
    }

    func testAReopenedPositionSurvivesAFailedUpdateAndALostResponseButNotNewerListening() async throws {
        for item in ["li-failed", "li-lost", "li-elsewhere"] {
            h.addProgress(item, account: AdoptionHarness.alice, position: 50, duration: 900, lastUpdate: AdoptionHarness.legacyUpdate)
        }
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        // The server's progress model (`MediaProgress.applyProgressUpdate` in 2.30): un-finishing
        // resets the position, and the change is stamped with `lastUpdate` when given, else now.
        let now = AdoptionHarness.legacyUpdate + 60_000
        var server: [String: (time: Double, finished: Bool, updated: Double)] = [:]
        for item in ["li-failed", "li-lost", "li-elsewhere"] { server[item] = (900, true, AdoptionHarness.legacyUpdate - 5_000) }
        for item in ["li-failed", "li-lost", "li-elsewhere"] {
            h.stub.route("GET", api + "/me/progress/" + item) { _ in
                let value = server[item]!
                return .json(200, ["libraryItemId": item, "currentTime": value.time, "duration": 900, "progress": value.time / 900, "isFinished": value.finished, "lastUpdate": value.updated])
            }
        }
        h.stub.route("GET", api + "/me") { _ in
            .json(200, StubUser.json(id: "user-1", progress: server.map { ["libraryItemId": $0.key, "currentTime": $0.value.time, "duration": 900, "progress": $0.value.time / 900,
                                                                          "isFinished": $0.value.finished, "lastUpdate": $0.value.updated] }))
        }
        var calls: [String: Int] = [:]
        for item in ["li-failed", "li-lost", "li-elsewhere"] {
            h.stub.route("PATCH", api + "/me/progress/" + item) { request in
                let body = request.json ?? [:]
                calls[item, default: 0] += 1
                if item == "li-failed", calls[item] == 2 { return .status(500) }
                var value = server[item]!
                if body["isFinished"] as? Bool == false, value.finished { value.finished = false; value.time = 0 }
                else if let time = body["currentTime"] as? Double { value.time = time }
                value.updated = (body["lastUpdate"] as? Double) ?? now
                server[item] = value
                if item == "li-elsewhere" { server[item] = (700, false, now) }  // listened on another device meanwhile
                if item == "li-lost", calls[item] == 1 { return .lost }
                return .status(200)
            }
        }

        _ = await h.adoption.sync()
        h.openStores()
        let second = await h.adoption.sync()
        _ = await h.adoption.sync()

        XCTAssertEqual(server["li-failed"]?.time, 50, "the full update is sent again after it failed")
        XCTAssertEqual(server["li-failed"]?.finished, false)
        XCTAssertEqual(server["li-lost"]?.time, 50, "a lost reopen response does not drop the position")
        XCTAssertEqual(server["li-elsewhere"]?.time, 700, "listening elsewhere after the reopen stays newer")
        XCTAssertEqual(second.progressPending, 0)
    }
}
