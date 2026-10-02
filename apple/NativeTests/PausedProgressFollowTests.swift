import XCTest

/// Another client's progress reaching a paused player, against a stub with the 2.30 server's
/// `/api/me` and `/api/session/local-all` shapes.
@MainActor final class PausedProgressFollowTests: XCTestCase {
    private var harness: AdoptionHarness!
    private let api = "/abs/api"
    private let itemID = "li-follow-" + UUID().uuidString
    private let gate = Gate()
    private var remote: (time: Double, updatedAt: Double?) = (0, 0)
    private var acceptListening = true
    private var alice: AccountIdentity { AdoptionHarness.identity(AdoptionHarness.alice) }

    /// Holds the next `/api/me` response until released, so the test can act during the request.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private let released = DispatchSemaphore(value: 0)
        private var armed = false
        func arm() { lock.lock(); armed = true; lock.unlock() }
        func passIfArmed() {
            lock.lock(); let wait = armed; armed = false; lock.unlock()
            if wait { released.wait() }
        }
        func release() { released.signal() }
    }

    override func setUp() async throws {
        harness = try AdoptionHarness()
        harness.signIn(AdoptionHarness.alice)
        harness.stub.route("GET", api + "/me") { [unowned self] _ in
            gate.passIfArmed()
            let progress: [String: Any] = ["libraryItemId": itemID, "currentTime": remote.time, "duration": 20,
                                           "lastUpdate": remote.updatedAt ?? Date().timeIntervalSince1970 * 1_000]
            return .json(200, StubUser.json(id: "user-1", progress: [progress]))
        }
        harness.stub.route("POST", api + "/session/local-all") { [unowned self] request in
            guard acceptListening else { return .status(500) }
            let ids = (request.json?["sessions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            return .json(200, ["results": ids.map { ["id": $0, "success": true] }])
        }
        try await openPausedAudio(at: 5)
    }

    override func tearDown() async throws {
        gate.release()
        try? await harness.player.stop()
        harness.cleanUp()
    }

    private func openPausedAudio(at position: Double) async throws {
        let file = harness.base.appendingPathComponent("follow.wav")
        try AdoptionHarness.wav(seconds: 20, tone: 440).write(to: file)
        let tracks = try JSONDecoder().decode([AudioTrack].self, from: Data(#"[{"contentUrl":"/audio.wav","startOffset":0,"duration":20}]"#.utf8))
        let audio = OfflineAudio(id: UUID().uuidString, account: alice,
                                 media: ListeningMedia(itemID: itemID, episodeID: nil, title: "Follow", author: "Synthetic", mediaType: "book", duration: 20, startTime: position),
                                 files: [file], tracks: tracks, chapters: [], serverPosition: position, serverUpdatedAt: 0)
        await harness.player.startOffline(audio)
        harness.player.pause()
        XCTAssertNotNil(harness.player.session, harness.player.error ?? "No playback session")
        try await harness.player.seek(to: position, autoplay: false)
        try await settleListening()
        remote = (14, nil)
    }

    /// A flush that joins a transfer already past its sending loop returns without sending later
    /// listening; letting that transfer retire first makes the second flush send everything.
    private func settleListening() async throws {
        await harness.player.restoreListening()
        try await Task.sleep(nanoseconds: 200_000_000)
        await harness.player.restoreListening()
    }

    private func meRequests() -> Int { harness.stub.requests("GET", api + "/me").count }

    private func lastSentPosition() -> Double? {
        harness.stub.requests("POST", api + "/session/local-all").last
            .flatMap { ($0.json?["sessions"] as? [[String: Any]])?.first?["currentTime"] as? Double }
    }

    private func waitForMeRequest(after count: Int) async throws {
        for _ in 0..<200 where meRequests() <= count { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertGreaterThan(meRequests(), count, "The follow never asked the server for progress")
    }

    func testPausedPlayerMovesToAnotherSessionsNewerProgressDurablyWithoutPlaying() async throws {
        let followed = await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertTrue(followed)
        XCTAssertEqual(harness.player.currentTime, 14, accuracy: 0.05)
        XCTAssertFalse(harness.player.wantsPlayback)
        XCTAssertFalse(harness.player.playing)

        await harness.player.restoreListening()
        XCTAssertEqual(try XCTUnwrap(lastSentPosition()), 14, accuracy: 0.05, "The followed position is not in the listening journal")
    }

    func testReconnectRefreshMovesThePausedPlayerToMissedProgress() async throws {
        let followed = await harness.player.refreshPausedProgress(account: alice)
        XCTAssertTrue(followed)
        XCTAssertEqual(harness.player.currentTime, 14, accuracy: 0.05)
        XCTAssertFalse(harness.player.wantsPlayback)
    }

    func testOwnSessionEchoOtherMediaAndOtherAccountsLeaveThePlayerInPlace() async throws {
        let player = harness.player!
        let own = try XCTUnwrap(player.session?.id)
        let before = meRequests()
        let echo = await player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: own)
        let otherItem = await player.followRemoteProgress(account: alice, itemID: "li-elsewhere", episodeID: nil, sessionID: "another-device")
        let otherEpisode = await player.followRemoteProgress(account: alice, itemID: itemID, episodeID: "ep-1", sessionID: "another-device")
        let otherAccount = await player.followRemoteProgress(account: AdoptionHarness.identity(AdoptionHarness.bob), itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertEqual([echo, otherItem, otherEpisode, otherAccount], [false, false, false, false])
        XCTAssertEqual(meRequests(), before, "Unrelated events must not fetch progress")
        XCTAssertEqual(player.currentTime, 5, accuracy: 0.05)
    }

    func testPlaybackIntentIsNeverMovedOrStopped() async throws {
        harness.player.resume()
        let followed = await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertFalse(followed)
        XCTAssertTrue(harness.player.wantsPlayback)
        XCTAssertLessThan(harness.player.currentTime, 10)
    }

    func testUnacknowledgedOwnListeningIsNotOverwrittenAndStaysQueued() async throws {
        acceptListening = false
        try await harness.player.seek(to: 7, autoplay: false)
        let followed = await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertFalse(followed)
        XCTAssertEqual(harness.player.currentTime, 7, accuracy: 0.05)

        acceptListening = true
        await harness.player.restoreListening()
        XCTAssertEqual(try XCTUnwrap(lastSentPosition()), 7, accuracy: 0.05)
    }

    // A 2.30 local-all sync overwrites server progress unless that progress is strictly newer, so
    // publishing the paused position first could replace the other device's movement.
    func testRemoteEventNeverPublishesPendingPausedListeningOrMovesOverIt() async throws {
        acceptListening = false
        try await harness.player.seek(to: 7, autoplay: false)
        try await settleListening()
        acceptListening = true
        let published = harness.stub.requests("POST", api + "/session/local-all").count
        let followed = await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertFalse(followed)
        XCTAssertEqual(harness.player.currentTime, 7, accuracy: 0.05)
        XCTAssertEqual(harness.stub.requests("POST", api + "/session/local-all").count, published, "The follow published the paused position")
    }

    func testOlderRemoteProgressDoesNotReplaceNewerLocalPosition() async throws {
        remote = (14, (Date().timeIntervalSince1970 - 3_600) * 1_000)
        let followed = await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device")
        XCTAssertFalse(followed)
        XCTAssertEqual(harness.player.currentTime, 5, accuracy: 0.05)
    }

    func testLocalSeekWhileProgressIsFetchedWins() async throws {
        let before = meRequests()
        gate.arm()
        let follow = Task { await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device") }
        try await waitForMeRequest(after: before)
        try await harness.player.seek(to: 3, autoplay: false)
        gate.release()
        let followed = await follow.value
        XCTAssertFalse(followed)
        XCTAssertEqual(harness.player.currentTime, 3, accuracy: 0.05)
    }

    func testPlayPressedWhileProgressIsFetchedWins() async throws {
        let before = meRequests()
        gate.arm()
        let follow = Task { await harness.player.followRemoteProgress(account: alice, itemID: itemID, episodeID: nil, sessionID: "another-device") }
        try await waitForMeRequest(after: before)
        harness.player.resume()
        gate.release()
        let followed = await follow.value
        XCTAssertFalse(followed)
        XCTAssertTrue(harness.player.wantsPlayback)
        XCTAssertLessThan(harness.player.currentTime, 10)
    }
}
