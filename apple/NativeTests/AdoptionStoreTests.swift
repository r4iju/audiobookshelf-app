import AVFoundation
import PDFKit
import XCTest

@MainActor final class AdoptionStoreTests: XCTestCase {
    private var h: AdoptionHarness!

    override func setUp() async throws { h = try AdoptionHarness() }
    override func tearDown() async throws { h.cleanUp() }

    private var alice: AccountIdentity { AdoptionHarness.identity(AdoptionHarness.alice) }

    func testAdoptedAudiobookPlaysOfflineAtItsLegacyPositionAndRemovingItKeepsEveryOriginal() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 2], position: 1.5)
        let outcome = try h.migrate()
        let originals = try h.originalDigests()

        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)

        // Visible once the same server user signs in, and after a relaunch.
        h.signIn(AdoptionHarness.alice)
        h.openStores()
        let entry = try XCTUnwrap(h.entry("li-audio"))
        XCTAssertEqual(entry.state, .ready)
        XCTAssertEqual(entry.account, alice)
        XCTAssertEqual(h.downloads.visible.map(\.id), [entry.id])
        let audio = try h.downloads.audio(entry)
        XCTAssertEqual(audio.serverPosition, 1.5)
        XCTAssertEqual(audio.serverUpdatedAt, AdoptionHarness.legacyUpdate)
        XCTAssertEqual(audio.media.duration, 3, accuracy: 0.001)
        XCTAssertEqual(audio.chapters.map(\.title), ["Chapter 1"])
        XCTAssertEqual(audio.files.count, 2)
        for (index, file) in audio.files.enumerated() {
            XCTAssertEqual(try Data(contentsOf: file), try h.legacyBytes("li-audio/0\(index + 1) Part.wav"))
            let decoded = try AVAudioPlayer(contentsOf: file)
            XCTAssertEqual(decoded.duration, [1.0, 2.0][index], accuracy: 0.01)
        }
        XCTAssertEqual(audio.tracks.map(\.startOffset), [0, 1])
        XCTAssertEqual(audio.tracks.map(\.contentUrl), ["/api/items/li-audio/file/ino-li-audio-1", "/api/items/li-audio/file/ino-li-audio-2"])

        await h.downloads.remove(entry, player: h.player)
        XCTAssertNil(h.entry("li-audio"))
        XCTAssertNil(h.downloads.error)
        XCTAssertNotNil(try h.migrator.committedOutcome())
        for file in outcome.downloads[0].tracks.compactMap(\.file) {
            XCTAssertEqual(AdoptionHarness.sha256(try Data(contentsOf: try h.migrator.fileURL(for: file))), file.sha256)
        }
        XCTAssertEqual(try h.originalDigests(), originals)
    }

    func testAdoptedPDFReopensOfflineOnItsLegacyPageAndEPUBKeepsItsLocation() async throws {
        try h.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 20), location: "12", fraction: 0.55)
        try h.addEbook("li-epub", format: "epub", data: Data("PK-synthetic-epub".utf8), location: "epubcfi(/6/14!/4/2/1:0)", fraction: 0.42)
        try h.addEbook("li-cbz", format: "cbz", data: Data("PK-synthetic-cbz".utf8), location: "7", fraction: 0.5)
        let outcome = try h.migrate()
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        h.openStores()

        let pdfEntry = try XCTUnwrap(h.entry("li-pdf"))
        XCTAssertEqual(pdfEntry.state, .ready)
        XCTAssertTrue(pdfEntry.tracks.isEmpty)
        XCTAssertEqual(pdfEntry.ebook?.ino, "ino-li-pdf")
        let pdfFile = try h.downloads.ebookURL(pdfEntry)
        XCTAssertEqual(try Data(contentsOf: pdfFile), try h.legacyBytes("li-pdf/book.pdf"))
        let document = try XCTUnwrap(PDFDocument(url: pdfFile))
        XCTAssertEqual(document.pageCount, 20)
        let saved = try XCTUnwrap(h.reading.position(account: alice, itemID: "li-pdf", format: "pdf"))
        XCTAssertEqual(saved.location, "12")
        // The PDF reader resumes at `Int(location)`, 1-based, as the legacy reader saved it.
        XCTAssertEqual(document.page(at: Int(saved.location)! - 1)?.string?.contains("Page 12"), true)
        XCTAssertEqual(saved.fraction, 0.55, accuracy: 0.0001)
        XCTAssertEqual(saved.updatedAt, AdoptionHarness.legacyUpdate)
        XCTAssertTrue(saved.pending)

        let epubEntry = try XCTUnwrap(h.entry("li-epub"))
        XCTAssertEqual(epubEntry.state, .ready)
        XCTAssertEqual(try Data(contentsOf: try h.downloads.ebookURL(epubEntry)), try h.legacyBytes("li-epub/book.epub"))
        XCTAssertEqual(h.reading.position(account: alice, itemID: "li-epub", format: "epub")?.location, "epubcfi(/6/14!/4/2/1:0)")

        // A deferred reader's format stays in the outcome, unconverted, and is reported as such.
        XCTAssertNil(h.entry("li-cbz"))
        XCTAssertNil(h.reading.position(account: alice, itemID: "li-cbz", format: "cbz"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-cbz" }?.status, .deferredFormat)
        XCTAssertEqual(report.reading.first { $0.libraryItemID == "li-cbz" }?.status, .deferredFormat)
        XCTAssertEqual(report.reading.first { $0.libraryItemID == "li-cbz" }?.location, "7")
        XCTAssertEqual(try h.migrator.committedOutcome(), outcome)
    }

    func testEveryDownloadedPodcastEpisodeBecomesItsOwnPlayableEntry() async throws {
        try h.addPodcast("li-pod", episodes: [("ep-1", 1), ("ep-2", 1.5)])
        _ = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)

        XCTAssertEqual(h.entries("li-pod").count, 2)
        for (episode, length) in [("ep-1", 1.0), ("ep-2", 1.5)] {
            let entry = try XCTUnwrap(h.entry("li-pod", episode: episode))
            XCTAssertEqual(entry.state, .ready)
            XCTAssertEqual(entry.media.mediaType, "podcast")
            XCTAssertEqual(entry.media.title, "Episode \(episode)")
            let audio = try h.downloads.audio(entry)
            XCTAssertEqual(try Data(contentsOf: audio.files[0]), try h.legacyBytes("li-pod/\(episode).wav"))
            XCTAssertEqual(try AVAudioPlayer(contentsOf: audio.files[0]).duration, length, accuracy: 0.01)
        }
    }

    func testRowsOfAnotherOrUnknownAccountStayQuarantinedInTheOutcome() async throws {
        try h.addAudiobook("li-moved", seconds: [1], position: 0.5, recordedUser: "user-9")
        try h.addAudiobook("li-orphan", seconds: [1], account: nil)
        try h.addAudiobook("li-audio", seconds: [1])
        let outcome = try h.migrate()
        XCTAssertTrue(outcome.issues.contains { $0.code == .accountMismatch })

        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)

        XCTAssertNotNil(h.entry("li-audio"))
        XCTAssertTrue(h.entries("li-moved").isEmpty)
        XCTAssertTrue(h.entries("li-orphan").isEmpty)
        XCTAssertNil(h.reading.position(account: alice, itemID: "li-moved", format: "pdf"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-moved" }?.status, .unattached)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-orphan" }?.status, .unattached)
        XCTAssertEqual(report.moduleIssues, outcome.issues)
        for issue in outcome.issues { XCTAssertTrue(report.issues.contains(issue.message), issue.message) }
        // The quarantined files are still the migrator's, intact, for a user-confirmed attach.
        for download in outcome.downloads where download.account == nil {
            for file in download.files.compactMap(\.file) {
                XCTAssertEqual(AdoptionHarness.sha256(try Data(contentsOf: try h.migrator.fileURL(for: file))), file.sha256)
            }
        }
    }

    func testDataTheNativeAppAlreadyHasWinsOverLegacyValues() async throws {
        try h.addAudiobook("li-audio", seconds: [1], position: 0.5)
        try h.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 20), location: "12", fraction: 0.55)
        var device = LegacyDeviceSettings()
        device.jumpForwardTime = 30
        device.jumpBackwardsTime = 15
        device.hapticFeedback = "HEAVY"
        device.downloadUsingCellular = "NEVER"
        device.languageCode = "de"
        h.snapshot.deviceSettings = device
        h.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1.35, chapterTrack: false)
        h.snapshot.preferences = ["theme": "black", "bookshelfListView": "1"]

        // Made in the preview after installation, before the import.
        let nativeID = UUID().uuidString
        let nativeGeneration = UUID().uuidString
        try FileManager.default.createDirectory(at: h.downloadsDirectory.appendingPathComponent(nativeID), withIntermediateDirectories: true)
        try AdoptionHarness.wav(seconds: 1, tone: 900).write(to: h.downloadsDirectory.appendingPathComponent(nativeID).appendingPathComponent("audio-0.wav"))
        let track = AudioTrack(contentUrl: "/api/items/li-audio/file/server-ino", mimeType: "audio/wav", metadata: .init(filename: "server.wav", ext: "wav"), startOffset: 0, duration: 1)
        let native = NativeDownloads.Entry(id: nativeID, account: alice, media: ListeningMedia(itemID: "li-audio", episodeID: nil, title: "Native", author: "", mediaType: "book", duration: 1, startTime: 0.9),
                                           tracks: [track], chapters: [], ebook: nil, serverPosition: 0.9, serverUpdatedAt: AdoptionHarness.legacyUpdate + 1, generation: nativeGeneration, finished: [0], state: .ready, error: nil)
        try writeManifest([native])
        h.openStores()
        try h.reading.update(account: alice, itemID: "li-pdf", format: "pdf", location: "3", fraction: 0.1, rotation: 90)
        h.defaults.set(45, forKey: "previewSkipForward")
        h.defaults.set("light", forKey: "previewTheme")

        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)

        XCTAssertEqual(h.entries("li-audio").map(\.id), [nativeID])
        XCTAssertEqual(h.entry("li-audio")?.generation, nativeGeneration)
        XCTAssertEqual(h.entry("li-audio")?.serverPosition, 0.9)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .keptNative)
        XCTAssertEqual(h.reading.position(account: alice, itemID: "li-pdf", format: "pdf")?.location, "3")
        XCTAssertEqual(h.reading.position(account: alice, itemID: "li-pdf", format: "pdf")?.rotation, 90)
        XCTAssertEqual(report.reading.first { $0.libraryItemID == "li-pdf" }?.status, .keptNative)
        XCTAssertNotNil(h.entry("li-pdf"), "a download the native app does not have is still adopted")

        XCTAssertEqual(h.defaults.integer(forKey: "previewSkipForward"), 45)
        XCTAssertEqual(h.defaults.string(forKey: "previewTheme"), "light")
        XCTAssertEqual(h.defaults.object(forKey: "previewSkipBackward") as? Int, 15)
        XCTAssertEqual(h.defaults.float(forKey: "previewPlaybackSpeed"), 1.35, accuracy: 0.0001)
        XCTAssertEqual(h.defaults.string(forKey: "previewHaptic"), "heavy")
        XCTAssertEqual(h.defaults.string(forKey: "previewDownloadsNetwork"), "never")
        XCTAssertEqual(h.defaults.object(forKey: "previewListLayout") as? Bool, true)
        XCTAssertTrue(report.settings.keptNative.contains("previewSkipForward"))
        XCTAssertTrue(report.settings.keptNative.contains("previewTheme"))
        XCTAssertTrue(report.settings.applied.contains("previewSkipBackward"))
        XCTAssertTrue(report.settings.retained.contains("languageCode"))
    }

    func testLegacyPlayerDisplayChoicesBecomeNativeOnlyWhereUnsetAndValid() async throws {
        // The visible choice (the `playerSettings` JSON) wins over the Realm copy the legacy app
        // handed to its iOS player; an explicit native choice wins over both.
        h.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1, chapterTrack: true)
        h.snapshot.preferences = ["playerSettings": #"{"useChapterTrack":false,"useTotalTrack":true,"scaleElapsedTimeBySpeed":false,"lockUi":true,"theme":"x"}"#]
        h.defaults.set(false, forKey: "previewLockPlayerControls")
        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)

        XCTAssertEqual(h.defaults.object(forKey: "previewChapterTrack") as? Bool, false)
        XCTAssertEqual(h.defaults.object(forKey: "previewTotalTrack") as? Bool, true)
        XCTAssertEqual(h.defaults.object(forKey: "previewScaleElapsedBySpeed") as? Bool, false)
        XCTAssertEqual(h.defaults.object(forKey: "previewLockPlayerControls") as? Bool, false)
        XCTAssertEqual(Set(report.settings.applied).intersection(["previewChapterTrack", "previewTotalTrack", "previewScaleElapsedBySpeed"]).count, 3)
        XCTAssertTrue(report.settings.keptNative.contains("previewLockPlayerControls"))
        XCTAssertTrue(report.settings.retained.contains("playerSettings.theme"), "\(report.settings.retained)")
        XCTAssertFalse(report.settings.retained.contains("playerSettings"))

        // Only the Realm copy of the chapter choice, values that are not booleans, and a native
        // total track already off: the chapter track would be off too, so it is not used.
        let second = try AdoptionHarness()
        defer { second.cleanUp() }
        second.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1, chapterTrack: false)
        second.snapshot.preferences = ["playerSettings": #"{"lockUi":"yes","useTotalTrack":1}"#]
        second.defaults.set(false, forKey: "previewTotalTrack")
        let kept = try await second.adoption.apply(outcome: try second.migrate(), migrator: second.migrator)

        XCTAssertNil(second.defaults.object(forKey: "previewChapterTrack"), "the chapter and total tracks are never both off")
        XCTAssertNil(second.defaults.object(forKey: "previewLockPlayerControls"))
        XCTAssertEqual(second.defaults.object(forKey: "previewTotalTrack") as? Bool, false)
        XCTAssertTrue(kept.settings.retained.contains("chapterTrack"), "\(kept.settings.retained)")
        XCTAssertTrue(kept.settings.retained.contains("playerSettings.lockUi"))
        XCTAssertTrue(kept.settings.retained.contains("playerSettings.useTotalTrack"))

        // Unreadable JSON is kept whole; the Realm chapter choice still applies.
        let third = try AdoptionHarness()
        defer { third.cleanUp() }
        third.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1, chapterTrack: false)
        third.snapshot.preferences = ["playerSettings": "{not json"]
        let fallback = try await third.adoption.apply(outcome: try third.migrate(), migrator: third.migrator)

        XCTAssertEqual(third.defaults.object(forKey: "previewChapterTrack") as? Bool, false)
        XCTAssertTrue(fallback.settings.applied.contains("previewChapterTrack"))
        XCTAssertTrue(fallback.settings.retained.contains("playerSettings"))
    }

    func testApplyingTheSameOutcomeAgainChangesNothing() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1], position: 0.5)
        try h.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 3), location: "2", fraction: 0.5)
        try h.addPodcast("li-pod", episodes: [("ep-1", 1)])
        h.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1.2, chapterTrack: true)
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let manifest = try Data(contentsOf: h.downloadsDirectory.appendingPathComponent("manifest.json"))
        let reading = try Data(contentsOf: h.readingFile)
        let files = h.localFiles()

        h.openStores()
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(try Data(contentsOf: h.downloadsDirectory.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: h.readingFile), reading)
        XCTAssertEqual(h.localFiles(), files)
        XCTAssertEqual(h.downloads.entries.count, 3)
        XCTAssertEqual(Set(report.downloads.map(\.status)), [.ready])
    }

    func testARepairAtTheSameFingerprintCompletesAPartialDownloadAndKeepsLaterNativeChanges() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 2], position: 0.5, missing: [1])
        try h.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 20), location: "12", fraction: 0.55)
        let first = try h.migrate()
        var report = try await h.adoption.apply(outcome: first, migrator: h.migrator)

        let partial = try XCTUnwrap(h.entry("li-audio"))
        XCTAssertEqual(partial.state, .failed)
        XCTAssertEqual(partial.finished, [0])
        XCTAssertEqual(partial.tracks.count, 2, "the missing part keeps its server reference so Retry fetches only it")
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .partial)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.adoptedParts, 1)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.totalParts, 2)
        XCTAssertFalse(report.summary.isEmpty)
        XCTAssertTrue(report.issues.contains { $0.contains("Title li-audio") })

        // Changes in the native app after the first import.
        try h.reading.update(account: alice, itemID: "li-pdf", format: "pdf", location: "15", fraction: 0.7, rotation: 0)
        h.defaults.set(60, forKey: "previewSkipForward")

        // The legacy file reappears; a new export of the same legacy data repairs a damaged
        // migration (here: an adopted file deleted under the migrator's root).
        try h.restorePendingFiles()
        let damaged = try XCTUnwrap(first.downloads.first { $0.libraryItemID == "li-pdf" }?.ebook?.file)
        try FileManager.default.removeItem(at: h.migrator.root.appendingPathComponent("Files").appendingPathComponent(damaged.path))
        XCTAssertThrowsError(try h.migrator.committedOutcome())
        let repaired = try h.migrator.migrate(try h.export())
        XCTAssertEqual(repaired.sourceFingerprint, first.sourceFingerprint)

        report = try await h.adoption.apply(outcome: repaired, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)

        let complete = try XCTUnwrap(h.entry("li-audio"))
        XCTAssertEqual(complete.id, partial.id)
        XCTAssertEqual(complete.state, .ready)
        XCTAssertEqual(complete.finished.sorted(), [0, 1])
        XCTAssertEqual(h.entries("li-audio").count, 1)
        let audio = try h.downloads.audio(complete)
        XCTAssertEqual(try Data(contentsOf: audio.files[1]), try h.legacyBytes("li-audio/02 Part.wav"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
        XCTAssertEqual(h.reading.position(account: alice, itemID: "li-pdf", format: "pdf")?.location, "15")
        XCTAssertEqual(h.defaults.integer(forKey: "previewSkipForward"), 60)
        XCTAssertEqual(try Data(contentsOf: try h.downloads.ebookURL(try XCTUnwrap(h.entry("li-pdf")))), try h.legacyBytes("li-pdf/book.pdf"))
    }

    func testAnAdoptedDownloadRemovedInTheNativeAppIsNotAddedAgain() async throws {
        try h.addAudiobook("li-audio", seconds: [1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        await h.downloads.remove(try XCTUnwrap(h.entry("li-audio")), player: h.player)
        XCTAssertNil(h.entry("li-audio"))

        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertNil(h.entry("li-audio"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .removedByUser)
    }

    func testAnApplyStoppedAfterAnyStepFinishesLikeAnUninterruptedOne() async throws {
        func scenario(_ harness: AdoptionHarness) throws {
            try harness.addAudiobook("li-audio", seconds: [1, 1], position: 0.5)
            try harness.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 3), location: "2", fraction: 0.5)
            harness.addSession("session-local", item: "li-audio", account: AdoptionHarness.alice, streamed: false, listened: 20, position: 0.5)
            harness.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1.2, chapterTrack: true)
            var device = LegacyDeviceSettings()
            device.jumpForwardTime = 30
            harness.snapshot.deviceSettings = device
        }
        // Files are named by the legacy file they carry; the synthetic PDF differs per render.
        func state(_ harness: AdoptionHarness) throws -> String {
            let legacy = Dictionary(try harness.originalDigests().filter { $0.key.hasPrefix(harness.documents.path) }.map { ($0.value, $0.key.replacingOccurrences(of: harness.documents.path, with: "")) }, uniquingKeysWith: { first, _ in first })
            let entries = harness.downloads.entries.sorted { $0.id < $1.id }.map { "\($0.id) \($0.media.libraryItemID) \($0.state) \($0.finished.sorted())" }
            let files = try harness.localFiles().map { path -> String in
                let url = URL(fileURLWithPath: harness.downloadsDirectory.path + path)
                var directory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                return directory.boolValue || url.lastPathComponent == "manifest.json" ? path : path + " " + { legacy[$0] ?? $0 }(AdoptionHarness.sha256(try Data(contentsOf: url)))
            }
            let reading = harness.reading.position(account: alice, itemID: "li-pdf", format: "pdf").map { "\($0.location) \($0.revision) \($0.pending)" } ?? "none"
            let settings = ["previewPlaybackSpeed", "previewSkipForward"].map { "\($0)=\(harness.defaults.object(forKey: $0) ?? "unset")" }
            return (entries + files + [reading] + settings).joined(separator: "\n")
        }

        let reference = try AdoptionHarness()
        defer { reference.cleanUp() }
        try scenario(reference)
        _ = try await reference.adoption.apply(outcome: try reference.migrate(), migrator: reference.migrator)
        let expected = try state(reference)

        for step in AdoptionStep.allCases {
            let harness = try AdoptionHarness()
            defer { harness.cleanUp() }
            try scenario(harness)
            let outcome = try harness.migrate()
            struct Stopped: Error {}
            harness.adoption.interruption = { if $0 == step { throw Stopped() } }
            do { _ = try await harness.adoption.apply(outcome: outcome, migrator: harness.migrator); XCTFail("\(step)") } catch {}

            harness.openStores()
            _ = try await harness.adoption.apply(outcome: outcome, migrator: harness.migrator)
            XCTAssertEqual(try state(harness), expected, "stopped after \(step)")
            XCTAssertFalse(harness.localFiles().contains { $0.contains("adopting-") }, "\(step)")

            // The unsent session is queued exactly once whatever step was interrupted.
            harness.signIn(AdoptionHarness.alice)
            harness.stub.route("POST", "/abs/api/session/local-all") { request in
                let id = ((request.json?["sessions"] as? [[String: Any]])?.first?["id"] as? String) ?? ""
                return .json(200, ["results": [["id": id, "success": true, "progressSynced": true]]])
            }
            harness.stub.route("GET", "/abs/api/me") { _ in .json(200, StubUser.json(id: "user-1")) }
            _ = await harness.adoption.sync()
            _ = await harness.adoption.sync()
            XCTAssertEqual(harness.stub.requests("POST", "/abs/api/session/local-all").count, 1, "\(step)")
        }
    }

    func testOneUnusableDownloadDoesNotHoldBackTheRestOfTheImport() async throws {
        try h.addAudiobook("li-good", seconds: [1], position: 0.5)
        try h.addAudiobook("li-empty", seconds: [1])
        // A track the legacy app recorded, and kept, as empty.
        try Data().write(to: h.documents.appendingPathComponent("li-empty/01 Part.wav"))
        h.snapshot.localItems[1].files[0].size = 0
        try h.addEbook("li-pdf", format: "pdf", data: AdoptionHarness.pdf(pages: 3), location: "2", fraction: 0.5)
        h.addSession("s-local", item: "li-good", account: AdoptionHarness.alice, streamed: false, listened: 20, position: 0.5)
        h.snapshot.playerSettings = LegacyPlayerSettings(playbackRate: 1.2, chapterTrack: true)
        let outcome = try h.migrate()

        for _ in 0..<2 {
            h.openStores()
            let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
            XCTAssertEqual(h.entry("li-good")?.state, .ready)
            XCTAssertEqual(h.entry("li-pdf")?.state, .ready)
            XCTAssertNil(h.entry("li-empty"))
            let empty = report.downloads.first { $0.libraryItemID == "li-empty" }
            XCTAssertEqual(empty?.status, .unavailable)
            XCTAssertTrue(report.issues.contains { $0.hasPrefix("Title li-empty") }, "\(report.issues)")
            XCTAssertEqual(report.listening.first { $0.account == AdoptionHarness.alice }?.pendingSessions, 1)
            XCTAssertEqual(h.reading.position(account: alice, itemID: "li-pdf", format: "pdf")?.location, "2")
            XCTAssertEqual(h.defaults.double(forKey: "previewPlaybackSpeed"), 1.2, accuracy: 0.0001)
        }
        XCTAssertFalse(h.localFiles().contains { $0.contains("adopting-") })
    }

    func testADownloadRemovedAfterAnInterruptedImportIsNotAddedAgain() async throws {
        try h.addAudiobook("li-audio", seconds: [1])
        let outcome = try h.migrate()
        struct Stopped: Error {}
        h.adoption.interruption = { if $0 == .manifestWritten { throw Stopped() } }
        do { _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator); XCTFail("the stop is reported") } catch {}
        h.adoption.interruption = nil

        h.openStores()
        h.signIn(AdoptionHarness.alice)
        await h.downloads.remove(try XCTUnwrap(h.entry("li-audio")), player: h.player)
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertNil(h.entry("li-audio"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .removedByUser)
    }

    func testAPartTheNativeAppDownloadedAgainIsLeftAsItIs() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let entry = try XCTUnwrap(h.entry("li-audio"))

        // The native downloader replaced part 1 with the server's bytes, and the migrated copy
        // has since gone from the migrator's store.
        let part = h.downloads.adoptionFile(entry, part: 1)
        let server = AdoptionHarness.wav(seconds: 1, tone: 900)
        try FileManager.default.removeItem(at: part)
        try server.write(to: part)
        let migrated = try XCTUnwrap(outcome.downloads[0].tracks[1].file)
        try FileManager.default.removeItem(at: try h.migrator.fileURL(for: migrated))

        h.openStores()
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        let kept = try XCTUnwrap(h.entry("li-audio"))
        XCTAssertEqual(kept.state, .ready)
        XCTAssertEqual(kept.finished.sorted(), [0, 1])
        XCTAssertEqual(try Data(contentsOf: part), server)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
    }

    func testAMissingAdoptedCopyIsPlacedAgainFromItsMigratedSource() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let entry = try XCTUnwrap(h.entry("li-audio"))
        let part = h.downloads.adoptionFile(entry, part: 1)
        try FileManager.default.removeItem(at: part)
        let originals = try h.originalDigests()

        // In the same app session, before the download store looks at its files again.
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(h.entry("li-audio")?.state, .ready)
        XCTAssertEqual(try Data(contentsOf: part), try h.legacyBytes("li-audio/02 Part.wav"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
        XCTAssertEqual(try h.originalDigests(), originals)
        let migrated = try XCTUnwrap(outcome.downloads[0].tracks[1].file)
        XCTAssertEqual(AdoptionHarness.sha256(try Data(contentsOf: try h.migrator.fileURL(for: migrated))), migrated.sha256)
    }

    func testAnAdoptedCopyDamagedInPlaceIsPlacedAgainWhenItsSourceIsIntact() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1])
        let outcome = try h.migrate()
        let migrated = try XCTUnwrap(outcome.downloads[0].tracks[1].file)
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let entry = try XCTUnwrap(h.entry("li-audio"))
        let part = h.downloads.adoptionFile(entry, part: 1)
        // As after a copy where hard links are unavailable: the migrated source and the adopted
        // part are two files with the same bytes.
        let source = try h.migrator.fileURL(for: migrated)
        let separate = source.deletingLastPathComponent().appendingPathComponent("separate")
        try FileManager.default.copyItem(at: source, to: separate)
        _ = try FileManager.default.replaceItemAt(source, withItemAt: separate)

        let handle = try FileHandle(forWritingTo: part)
        try handle.seek(toOffset: 100)
        handle.write(Data(repeating: 0x7f, count: 64))
        try handle.close()

        h.openStores()
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(h.entry("li-audio")?.state, .ready)
        XCTAssertEqual(try Data(contentsOf: part), try h.legacyBytes("li-audio/02 Part.wav"))
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
        XCTAssertEqual(AdoptionHarness.sha256(try Data(contentsOf: try h.migrator.fileURL(for: migrated))), migrated.sha256)
    }

    /// An adopted part damaged in place, with its migrated source kept apart and intact.
    private func damageAdoptedPart(_ outcome: MigrationOutcome) throws -> URL {
        let migrated = try XCTUnwrap(outcome.downloads[0].tracks[1].file)
        let part = h.downloads.adoptionFile(try XCTUnwrap(h.entry("li-audio")), part: 1)
        let source = try h.migrator.fileURL(for: migrated)
        let separate = source.deletingLastPathComponent().appendingPathComponent("separate")
        try FileManager.default.copyItem(at: source, to: separate)
        _ = try FileManager.default.replaceItemAt(source, withItemAt: separate)
        let handle = try FileHandle(forWritingTo: part)
        try handle.seek(toOffset: 100)
        handle.write(Data(repeating: 0x7f, count: 64))
        try handle.close()
        return part
    }

    func testARepairThatCannotBeMovedIntoPlaceIsLeftForRetryAndRepairedLater() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let part = try damageAdoptedPart(outcome)
        let folder = part.deletingLastPathComponent().path
        h.openStores()
        // The entry's folder stops accepting new names after the repair was staged.
        h.adoption.beforePlacing = { target in if target.path == part.path { chmod(folder, 0o555) } }
        defer { chmod(folder, 0o755) }

        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(h.entry("li-audio")?.finished, [0], "a damaged part that was not replaced is not ready")
        XCTAssertEqual(h.entry("li-audio")?.state, .failed)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .partial)

        chmod(folder, 0o755)
        h.adoption.beforePlacing = nil
        let repaired = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(h.entry("li-audio")?.state, .ready)
        XCTAssertEqual(try Data(contentsOf: part), try h.legacyBytes("li-audio/02 Part.wav"))
        XCTAssertEqual(repaired.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
    }

    func testAnImportStoppedBeforeARepairMovedIntoPlaceRepairsItNextTime() async throws {
        try h.addAudiobook("li-audio", seconds: [1, 1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        let part = try damageAdoptedPart(outcome)
        h.openStores()
        struct Stopped: Error {}
        h.adoption.interruption = { if $0 == .planRecorded { throw Stopped() } }
        do { _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator); XCTFail("the stop is reported") } catch {}

        h.openStores()
        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertEqual(try Data(contentsOf: part), try h.legacyBytes("li-audio/02 Part.wav"), "the damaged part is still adoption's to repair")
        XCTAssertEqual(h.entry("li-audio")?.state, .ready)
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-audio" }?.status, .ready)
    }

    func testTheSummaryOnlyCallsDownloadsOfTheSignedInAccountReady() async throws {
        try h.addAudiobook("li-alice", seconds: [1])
        try h.addAudiobook("li-bob", seconds: [1], account: AdoptionHarness.bob)
        h.signIn(AdoptionHarness.alice)
        h.openStores()
        let report = try await h.adoption.apply(outcome: try h.migrate(), migrator: h.migrator)

        XCTAssertTrue(report.summary.contains("1 download is ready to play or read offline."), report.summary)
        XCTAssertTrue(report.summary.contains("1 download is ready once its account is signed in."), report.summary)
    }

    func testARemovalOrANativeFileArrivingWhileAnImportPlacesFilesIsNeverOverwritten() async throws {
        try h.addAudiobook("li-removed", seconds: [1, 1])
        try h.addAudiobook("li-written", seconds: [1, 1])
        let outcome = try h.migrate()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice)
        let removed = try XCTUnwrap(h.entry("li-removed")), written = try XCTUnwrap(h.entry("li-written"))
        let removedPart = h.downloads.adoptionFile(removed, part: 1), writtenPart = h.downloads.adoptionFile(written, part: 1)
        try FileManager.default.removeItem(at: removedPart)
        try FileManager.default.removeItem(at: writtenPart)
        let originals = try h.originalDigests()
        let server = AdoptionHarness.wav(seconds: 1, tone: 900)
        let downloads = h.downloads!, player = h.player!
        // While the next import works off the main actor, the user removes one download and the
        // native downloader finishes the missing part of the other.
        h.adoption.beforePlacing = { target in
            if target.path == removedPart.path {
                let done = DispatchSemaphore(value: 0)
                Task { @MainActor in await downloads.remove(removed, player: player); done.signal() }
                done.wait()
            } else if target.path == writtenPart.path {
                try? server.write(to: target)
            }
        }

        let report = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)

        XCTAssertNil(h.entry("li-removed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.downloadsDirectory.appendingPathComponent(removed.id).path), "nothing is placed for a removed download")
        XCTAssertEqual(report.downloads.first { $0.libraryItemID == "li-removed" }?.status, .removedByUser)
        XCTAssertEqual(try Data(contentsOf: writtenPart), server, "the native app's file is kept")
        XCTAssertEqual(h.entry("li-written")?.generation, written.generation)
        XCTAssertEqual(try h.originalDigests(), originals)
        XCTAssertFalse(h.localFiles().contains { $0.contains("adopting-") })
    }

    func testALegacyNetworkSettingReachesTheRunningDownloadsThroughTheirChangeNotice() async throws {
        // The production boundary: `AppleNetworkPolicy` reads the standard defaults. Every key an
        // import may write there is put back afterwards.
        let standard = UserDefaults.standard
        let keys = [AppleNetworkPolicy.downloadsKey, AppleNetworkPolicy.streamingKey, "previewDownloadCellular", "previewSkipForward", "previewSkipBackward", "previewHaptic",
                    "previewResumeRewind", "previewMediaSeeking", "previewSleepFade", "previewPlaybackSpeed", "previewTheme", "previewListLayout", "previewEPUBPreferences", "nativeDeviceID"]
        let saved = keys.map { standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) } } }
        for key in [AppleNetworkPolicy.downloadsKey, AppleNetworkPolicy.streamingKey, "previewDownloadCellular"] { standard.removeObject(forKey: key) }

        // A download this app queued under the policy in force then; nobody is signed in, so it
        // does not start.
        let generation = UUID().uuidString
        let track = AudioTrack(contentUrl: "/api/items/li-native/file/ino", mimeType: "audio/wav", metadata: .init(filename: "a.wav", ext: "wav"), startOffset: 0, duration: 1)
        var queued = NativeDownloads.Entry(id: UUID().uuidString, account: alice, media: ListeningMedia(itemID: "li-native", episodeID: nil, title: "Native", author: "", mediaType: "book", duration: 1, startTime: 0),
                                           tracks: [track], chapters: [], ebook: nil, serverPosition: 0, serverUpdatedAt: 0, generation: generation, finished: [], state: .queued, error: nil)
        queued.networkPolicy = AppleNetworkPolicy.never.rawValue
        try writeManifest([queued])
        h.openStores()
        XCTAssertEqual(h.entry("li-native")?.generation, generation)
        var device = LegacyDeviceSettings()
        device.downloadUsingCellular = "ALWAYS"
        h.snapshot.deviceSettings = device
        let adoption = NativeMigrationAdoption(downloads: h.downloads, reading: h.reading, api: h.api, defaults: standard, directory: h.adoptionDirectory, session: h.session)

        let report = try await adoption.apply(outcome: try h.migrate(), migrator: h.migrator)

        XCTAssertTrue(report.settings.applied.contains(AppleNetworkPolicy.downloadsKey))
        XCTAssertEqual(AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey), .always)
        for _ in 0..<100 where h.entry("li-native")?.networkPolicy != "always" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(h.entry("li-native")?.networkPolicy, "always", "the queued download follows the new policy")
        XCTAssertNotEqual(h.entry("li-native")?.generation, generation, "work started under the old policy is superseded")
    }

    private func writeManifest(_ entries: [NativeDownloads.Entry]) throws {
        struct Manifest: Encodable { let version: Int; let entries: [NativeDownloads.Entry] }
        try FileManager.default.createDirectory(at: h.downloadsDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Manifest(version: 1, entries: entries)).write(to: h.downloadsDirectory.appendingPathComponent("manifest.json"))
    }
}

enum StubUser {
    static func json(id: String, progress: [[String: Any]] = []) -> [String: Any] {
        ["id": id, "username": id, "type": "user", "mediaProgress": progress, "permissions": ["download": true], "bookmarks": []]
    }
}
