import MediaPlayer
import XCTest

@MainActor final class ChapterMediaControlsTests: XCTestCase {
    private var harness: AdoptionHarness!
    private var savedChapterPreference: Any?

    override func setUp() async throws {
        savedChapterPreference = UserDefaults.standard.object(forKey: "previewChapterTrack")
        UserDefaults.standard.set(true, forKey: "previewChapterTrack")
        harness = try AdoptionHarness()
        harness.signIn(AdoptionHarness.alice)
    }

    override func tearDown() async throws {
        try? await harness.player.stop()
        harness.cleanUp()
        if let savedChapterPreference { UserDefaults.standard.set(savedChapterPreference, forKey: "previewChapterTrack") }
        else { UserDefaults.standard.removeObject(forKey: "previewChapterTrack") }
    }

    private func openAudio() async throws {
        let file = harness.base.appendingPathComponent("chapter-controls.wav")
        try AdoptionHarness.wav(seconds: 20, tone: 440).write(to: file)
        let chapters = try JSONDecoder().decode([Chapter].self, from: Data(#"[{"id":0,"title":"Opening","start":0,"end":8},{"id":1,"title":"The second chapter","start":8,"end":20}]"#.utf8))
        let tracks = try JSONDecoder().decode([AudioTrack].self, from: Data(#"[{"contentUrl":"/audio.wav","startOffset":0,"duration":20}]"#.utf8))
        let audio = OfflineAudio(id: UUID().uuidString, account: AdoptionHarness.identity(AdoptionHarness.alice),
                                 media: ListeningMedia(itemID: UUID().uuidString, episodeID: nil, title: "Chapter controls", author: "Synthetic", mediaType: "book", duration: 20, startTime: 11),
                                 files: [file], tracks: tracks, chapters: chapters, serverPosition: 11, serverUpdatedAt: Date().timeIntervalSince1970 * 1_000)
        await harness.player.startOffline(audio)
        harness.player.pause()
        XCTAssertNotNil(harness.player.session, harness.player.error ?? "No playback session")
        try await harness.player.seek(to: 11, autoplay: false)
    }

    func testChapterModePublishesRelativeSystemTimeAndUpdatesWhenSeekingIntoAnotherChapter() async throws {
        try await openAudio()
        let second = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(try XCTUnwrap(second[MPMediaItemPropertyPlaybackDuration] as? Double), 12, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(second[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double), 3, accuracy: 0.05)
        try await harness.player.seek(to: 4, autoplay: false)
        let first = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(try XCTUnwrap(first[MPMediaItemPropertyPlaybackDuration] as? Double), 8, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(first[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double), 4, accuracy: 0.05)
    }

    func testSystemScrubbingUsesChapterCoordinatesAndClampsToItsEnd() async throws {
        try await openAudio()
        try await harness.player.seekFromMediaControls(to: 2)
        XCTAssertEqual(harness.player.currentTime, 10, accuracy: 0.05)
        try await harness.player.seekFromMediaControls(to: 100)
        XCTAssertEqual(harness.player.currentTime, 20, accuracy: 0.05)
    }

    func testChapterModePublishesItsTitleAndNumberWhileRetainingTheBookName() async throws {
        try await openAudio()
        let information = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(information[MPMediaItemPropertyTitle] as? String, "The second chapter")
        XCTAssertEqual(information[MPMediaItemPropertyAlbumTitle] as? String, "Chapter controls")
        XCTAssertEqual(information[MPNowPlayingInfoPropertyChapterNumber] as? Int, 2)
        XCTAssertEqual(information[MPNowPlayingInfoPropertyChapterCount] as? Int, 2)
    }
}
