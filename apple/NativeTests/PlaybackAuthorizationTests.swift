import XCTest

/// The production player streaming real audio from `verification.fixture` while the server renews or
/// revokes the signed-in session. Run through `apple/scripts/verify-playback-authorization.sh`, which
/// starts the fixture and passes its address; without it these tests are skipped.
@MainActor final class PlaybackAuthorizationTests: XCTestCase {
    private var fixture: String!
    private var credentials: MemoryCredentials!
    private var api: APIClient!
    private var player: ApplePlayback!
    private var base: URL!
    private let qa = "00000000-0000-4000-8000-000000000001"
    private let other = "00000000-0000-4000-8000-000000000002"

    override func setUp() async throws {
        guard let address = ProcessInfo.processInfo.environment["ABS_PLAYBACK_FIXTURE"] else {
            throw XCTSkip("Needs the synthetic fixture started by verify-playback-authorization.sh")
        }
        fixture = address
        base = FileManager.default.temporaryDirectory.appendingPathComponent("playback-auth-\(UUID().uuidString)", isDirectory: true)
        // Each test starts like a fresh install, with no listening left by an earlier run.
        try? FileManager.default.removeItem(at: ListeningSync.file)
        try await control("configure", ["mode": "baseline"])
        credentials = MemoryCredentials()
        api = APIClient(store: credentials, session: URLSession(configuration: .ephemeral))
        try await api.login(server: address, username: "qa", password: "qa")
        player = ApplePlayback(api: api, progressResets: base.appendingPathComponent("progress-resets.json"))
    }

    override func tearDown() async throws {
        try? await player?.stop()
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    @discardableResult
    private func control(_ name: String, _ body: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: fixture + "/__fixture__/" + name)!)
        request.httpMethod = name == "observations" ? "GET" : "POST"
        if request.httpMethod == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Fixture control \(name) failed")
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func observations() async throws -> (requests: [String], reports: [[String: Any]]) {
        let observed = try await control("observations")
        let requests = (observed["requests"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
        let reports = (observed["reports"] as? [[String: Any]] ?? []).filter { $0["path"] as? String == "/api/session/local-all" }
        return (requests, reports)
    }

    private func eventually(_ seconds: Double, _ description: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out: \(description). error=\(player.error ?? "nil") playing=\(player.playing) wants=\(player.wantsPlayback) seeking=\(player.seeking) preparing=\(player.preparing) track=\(player.trackIndex) time=\(player.currentTime)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func startStreaming() async throws {
        let item = try await api.item(id: "book-0")
        await player.start(item: item)
        XCTAssertNil(player.error)
        try await eventually(20, "streamed audio playing past 6.5 s") { player.playing && player.currentTime > 6.5 }
    }

    /// Story 12: the server stops accepting the access token while audio plays. The next file must load with a
    /// renewed token, from one refresh shared with listening sync, and the renewal must be saved.
    func testExpiredAccessDuringStreamingRenewsOnceAndPlaybackContinuesIntoTheNextFile() async throws {
        try await startStreaming()
        let before = try await observations().requests.count
        try await control("expire-access")

        try await eventually(12, "playback crossing into the second file") { player.trackIndex == 1 && player.currentTime > 9.5 }
        try await eventually(3, "audio playing in the second file") { player.playing }
        XCTAssertNil(player.error)
        XCTAssertFalse(player.needsSignIn)
        XCTAssertEqual(credentials.value?.accessToken, "fresh-r1", "The renewed token was not saved")

        player.pause()
        await player.restoreListening()
        let observed = try await observations()
        XCTAssertEqual(observed.requests.dropFirst(before).filter { $0 == "/auth/refresh" }.count, 1, "Renewal was not coordinated")
        let delivered = try XCTUnwrap(observed.reports.last)
        XCTAssertEqual(delivered["userId"] as? String, qa)
        XCTAssertGreaterThan(delivered["currentTime"] as? Double ?? 0, 9.5)
    }

    /// Story 14: the server signs the account out while audio streams. Audio must stop rather than play on
    /// unnoticed, the player must ask to sign in, and the listening must survive another account signing in
    /// until the same account signs in again.
    func testRevocationDuringStreamingStopsAudioAsksToSignInAndKeepsListeningForThatAccount() async throws {
        try await startStreaming()
        try await control("revoke", ["username": "qa"])

        try await eventually(15, "audio stopping after revocation") { !player.playing && !player.wantsPlayback }
        try await eventually(5, "a sign-in request") { player.needsSignIn }
        XCTAssertNotNil(player.session, "The open media must stay in place to resume after signing in")
        let stoppedAt = player.currentTime
        XCTAssertGreaterThan(stoppedAt, 6.5)

        player.resume()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(player.playing, "Audio played again for a revoked account")
        XCTAssertTrue(player.needsSignIn)

        // The connection screen's order: close the player, sign in, then deliver saved listening.
        try await player.suspendForConnectionChange()
        try await api.login(server: fixture, username: "qa-other", password: "qa")
        await player.restoreListening()
        var observed = try await observations()
        XCTAssertFalse(observed.reports.contains { $0["userId"] as? String == other }, "Another account sent the revoked account's listening")

        try await player.suspendForConnectionChange()
        try await api.login(server: fixture, username: "qa", password: "qa")
        await player.restoreListening()
        observed = try await observations()
        let delivered = try XCTUnwrap(observed.reports.last { $0["userId"] as? String == qa }, "Listening was lost")
        XCTAssertEqual(delivered["currentTime"] as? Double ?? 0, stoppedAt, accuracy: 0.6)
        XCTAssertNil(player.error)
    }

    /// Story 14 for downloaded audio, which needs no server to play: the first rejected sync must stop it too.
    func testRevocationDuringDownloadedPlaybackStopsAudioAtTheNextSync() async throws {
        let file = base.appendingPathComponent("downloaded.wav")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try AdoptionHarness.wav(seconds: 20, tone: 330).write(to: file)
        let tracks = try JSONDecoder().decode([AudioTrack].self, from: Data(#"[{"contentUrl":"/audio/0","startOffset":0,"duration":20}]"#.utf8))
        let account = try await api.currentAccount()
        let audio = OfflineAudio(id: UUID().uuidString, account: account,
                                 media: ListeningMedia(itemID: "book-0", episodeID: nil, title: "Downloaded", author: "QA Studio", mediaType: "book", duration: 20, startTime: 2),
                                 files: [file], tracks: tracks, chapters: [], serverPosition: 2, serverUpdatedAt: 0)
        await player.startOffline(audio)
        try await eventually(5, "downloaded audio playing") { player.playing && player.currentTime > 2.5 }
        try await control("revoke", ["username": "qa"])

        player.sync()
        try await eventually(5, "audio stopping after the rejected sync") { !player.playing && !player.wantsPlayback }
        XCTAssertTrue(player.needsSignIn)
        player.resume()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(player.playing, "Audio played again for a revoked account")
    }
}
