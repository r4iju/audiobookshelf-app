import XCTest
@testable import AudiobookshelfTV

@MainActor final class MediaRestartTests: XCTestCase {
    private final class Player: RestartablePlayback {
        var session: PlaybackSession?
        var itemID: String? = "book-0"
        var episodeID: String?
        var wantsPlayback = true
        var error: String? = "Audio could not be played."
        var isProgressFailure = false
        var started: [String] = []
        init() { session = MediaRestartTests.session("session-1") }
        func start(item: AudiobookshelfTV.LibraryItem, episode: AudiobookshelfTV.Episode?) async { started.append(item.id) }
    }

    nonisolated static func session(_ id: String) -> PlaybackSession {
        try! JSONDecoder().decode(PlaybackSession.self, from: Data(#"{"id":"\#(id)","currentTime":6,"duration":20,"audioTracks":[{"contentUrl":"/audio/0","startOffset":0,"duration":20}]}"#.utf8))
    }

    private static let book = try! JSONDecoder().decode(AudiobookshelfTV.LibraryItem.self, from: Data(#"{"id":"book-0","mediaType":"book","media":{"metadata":{"title":"A Story"},"duration":20}}"#.utf8))

    /// Holds the item fetch open so the test can change the player while the restart waits.
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        var fail = false
        func fetch(_ id: String) async throws -> AudiobookshelfTV.LibraryItem {
            await withCheckedContinuation { continuation = $0 }
            if fail { throw URLError(.timedOut) }
            return MediaRestartTests.book
        }
        func open() { continuation?.resume(); continuation = nil }
    }

    private func restart(_ player: Player, gate: Gate, account: UUID = UUID(), currentAccount: (() -> UUID)? = nil, meanwhile: () -> Void) async -> String? {
        let task = Task { await MediaRestart.run(player, account: currentAccount ?? { account }, fetch: gate.fetch) }
        while gate.continuation == nil { await Task.yield() }
        meanwhile()
        gate.open()
        return await task.value
    }

    func testRestartsTheFailedMediaWhenNothingChanged() async {
        let player = Player(), gate = Gate()
        let message = await restart(player, gate: gate) {}
        XCTAssertNil(message)
        XCTAssertEqual(player.started, ["book-0"])
    }

    func testANewerSessionForTheSameMediaIsNotRestartedOrBlamed() async {
        let player = Player(), gate = Gate()
        gate.fail = true
        let message = await restart(player, gate: gate) {
            player.session = Self.session("session-2"); player.error = nil
        }
        XCTAssertNil(message, "The old attempt's failure must not appear on the replacement session")
        let retry = Gate()
        player.error = "Audio could not be played."
        _ = await restart(player, gate: retry) { player.session = Self.session("session-3") }
        XCTAssertEqual(player.started, [], "A later session for the same book must not be restarted by an older request")
    }

    func testAPauseOrRecoveryWhileWaitingIsRespected() async {
        let paused = Player(), gate = Gate()
        _ = await restart(paused, gate: gate) { paused.wantsPlayback = false }
        XCTAssertEqual(paused.started, [], "A pause during the fetch wins over the restart")

        let recovered = Player(), again = Gate()
        _ = await restart(recovered, gate: again) { recovered.error = nil }
        XCTAssertEqual(recovered.started, [], "A seek that recovered the media must not be overridden")
    }

    func testAnAccountSwitchCancelsTheRestart() async {
        let player = Player(), gate = Gate()
        var account = UUID()
        let message = await restart(player, gate: gate, currentAccount: { account }) { account = UUID() }
        XCTAssertNil(message)
        XCTAssertEqual(player.started, [])
    }
}
