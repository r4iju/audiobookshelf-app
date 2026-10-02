import AVFoundation
import XCTest

/// Observation probe for story 34, not a committed regression: posts the system's interruption and
/// route-change notifications to the production `ApplePlayback` handlers while downloaded audio is
/// actually decoding, and prints what the player does. Assertions state the documented policy.
@MainActor final class InterruptionRouteProbe: XCTestCase {
    private var harness: AdoptionHarness!
    private var player: ApplePlayback { harness.player }

    override func setUp() async throws {
        harness = try AdoptionHarness()
        harness.signIn(AdoptionHarness.alice)
        harness.stub.route("GET", "/abs/api/me") { _ in .json(200, StubUser.json(id: "user-1", progress: [])) }
        harness.stub.route("POST", "/abs/api/session/local-all") { request in
            let ids = (request.json?["sessions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            return .json(200, ["results": ids.map { ["id": $0, "success": true] }])
        }
        let file = harness.base.appendingPathComponent("probe.wav")
        try AdoptionHarness.wav(seconds: 60, tone: 330).write(to: file)
        let tracks = try JSONDecoder().decode([AudioTrack].self, from: Data(#"[{"contentUrl":"/audio.wav","startOffset":0,"duration":60}]"#.utf8))
        let audio = OfflineAudio(id: UUID().uuidString, account: AdoptionHarness.identity(AdoptionHarness.alice),
                                 media: ListeningMedia(itemID: "li-probe-" + UUID().uuidString, episodeID: nil, title: "Probe", author: "Synthetic", mediaType: "book", duration: 60, startTime: 5),
                                 files: [file], tracks: tracks, chapters: [], serverPosition: 5, serverUpdatedAt: 0)
        await player.startOffline(audio)
        try await wait("playing", 5) { self.player.playing && self.player.currentTime > 5.5 }
    }

    override func tearDown() async throws {
        try? await harness.player.stop()
        harness.cleanUp()
    }

    private func wait(_ what: String, _ seconds: Double, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out: \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    private func settle(_ seconds: Double = 1.5) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private func observe(_ label: String) {
        print("PROBE \(name) \(label): playing=\(player.playing) wantsPlayback=\(player.wantsPlayback) position=\(String(format: "%.2f", player.currentTime)) session=\(player.session != nil) error=\(player.error ?? "nil")")
    }

    private func interruption(began: Bool, shouldResume: Bool = false, suspended: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: (began ? AVAudioSession.InterruptionType.began : .ended).rawValue]
        if !began { info[AVAudioSessionInterruptionOptionKey] = shouldResume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0 }
        if suspended { info[AVAudioSessionInterruptionReasonKey] = AVAudioSession.InterruptionReason.appWasSuspended.rawValue }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    private func route(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    func testCallThatAllowsResumingPausesKeepsPositionAndResumes() async throws {
        observe("before")
        interruption(began: true)
        try await wait("paused by interruption", 3) { !self.player.playing }
        let held = player.currentTime
        try await settle(2)
        observe("interrupted")
        XCTAssertFalse(player.wantsPlayback)
        XCTAssertEqual(player.currentTime, held, accuracy: 0.05, "Position moved while interrupted")
        interruption(began: false, shouldResume: true)
        try await wait("resumed", 4) { self.player.playing }
        try await settle()
        observe("resumed")
        XCTAssertGreaterThan(player.currentTime, held, "Did not continue from the held position")
        XCTAssertLessThan(player.currentTime, held + 3, "Jumped after resuming")
    }

    func testInterruptionEndingWithoutResumeOptionStaysPaused() async throws {
        interruption(began: true)
        try await wait("paused", 3) { !self.player.playing }
        interruption(began: false, shouldResume: false)
        try await settle(2)
        observe("ended without shouldResume")
        XCTAssertFalse(player.playing); XCTAssertFalse(player.wantsPlayback)
    }

    func testAppSuspensionInterruptionNeverResumesByItself() async throws {
        interruption(began: true, suspended: true)
        try await wait("paused", 3) { !self.player.playing }
        interruption(began: false, shouldResume: true)
        try await settle(2)
        observe("suspended then shouldResume")
        XCTAssertFalse(player.playing)
    }

    func testPausedListenerIsNotStartedByAnInterruptionEnding() async throws {
        player.pause()
        interruption(began: true)
        try await settle(0.5)
        interruption(began: false, shouldResume: true)
        try await settle(2)
        observe("paused before interruption")
        XCTAssertFalse(player.playing)
    }

    func testControlDuringInterruptionSupersedesAutomaticResume() async throws {
        interruption(began: true)
        try await wait("paused", 3) { !self.player.playing }
        player.resume(); try await settle(0.5); player.pause()
        observe("listener resumed then paused during interruption")
        interruption(began: false, shouldResume: true)
        try await settle(2)
        observe("after ended shouldResume")
        XCTAssertFalse(player.playing)
    }

    func testStoppingDuringInterruptionDoesNotResumeAnything() async throws {
        interruption(began: true)
        try await wait("paused", 3) { !self.player.playing }
        try await player.stop()
        interruption(began: false, shouldResume: true)
        try await settle(2)
        observe("stopped during interruption")
        XCTAssertFalse(player.playing); XCTAssertNil(player.session)
    }

    func testLongInterruptionRewindsOnResumeLikeAManualResume() async throws {
        interruption(began: true)
        try await wait("paused", 3) { !self.player.playing }
        let held = player.currentTime
        try await settle(11)
        interruption(began: false, shouldResume: true)
        try await wait("resumed", 4) { self.player.playing }
        observe("resumed after 11 s (held \(String(format: "%.2f", held)))")
        XCTAssertEqual(player.currentTime, max(held - 3, 0), accuracy: 1)
    }

    func testHeadphonesRemovedPausesAndReconnectingDoesNotResume() async throws {
        route(.oldDeviceUnavailable)
        try await wait("paused by route loss", 3) { !self.player.playing }
        let held = player.currentTime
        observe("old device unavailable")
        XCTAssertFalse(player.wantsPlayback)
        route(.newDeviceAvailable)
        try await settle(2)
        observe("new device available")
        XCTAssertFalse(player.playing)
        XCTAssertEqual(player.currentTime, held, accuracy: 0.05)
        await player.restoreListening()
        let sent = harness.stub.requests("POST", "/abs/api/session/local-all").last
            .flatMap { ($0.json?["sessions"] as? [[String: Any]])?.first?["currentTime"] as? Double }
        print("PROBE \(name) delivered position=\(sent.map { String(format: "%.2f", $0) } ?? "nil")")
        XCTAssertEqual(try XCTUnwrap(sent), held, accuracy: 0.6)
    }

    func testOtherRouteChangesKeepPlaying() async throws {
        for reason: AVAudioSession.RouteChangeReason in [.newDeviceAvailable, .categoryChange, .override, .routeConfigurationChange] {
            route(reason)
            try await settle(0.7)
            observe("route \(reason.rawValue)")
            XCTAssertTrue(player.playing, "Route change \(reason.rawValue) stopped audio")
        }
    }
}
