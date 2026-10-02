import XCTest

/// QA probe, not part of the suite: the production migrator and adoption against the isolated Audiobookshelf 2.30.0
/// container `abs-apple-qa` (19890), signed in as the synthetic `qa-other`. The runner plays the legacy app's server
/// side first: it opens two streamed sessions and reports some listening, restarts the container after the first,
/// and saves a newer server position for Catalog Volume 03. Session ids arrive as ABS_RS_OPEN and ABS_RS_RESTARTED.
@MainActor final class RealServerAdoptionProbe: XCTestCase {
    static let server = "http://127.0.0.1:19890"
    static let user = "dec9bf27-e818-46e2-a99f-0a6fe335eaf8"
    static let salt = "880c5e1a-475a-40ea-b68c-7b86d320472d"
    static let longStory = "1d853118-1beb-41d1-85d2-21f699e55a79"
    static let volume1 = "5b4b730d-54a0-430d-8bbe-b63b8f018007"
    static let volume2 = "636e9611-c7a6-490a-8cfa-d2a27766f8ca"
    static let volume3 = "fe3e135c-afb7-4f1a-8cb0-b40d86c452cb"

    private var base: URL!

    override func tearDown() {
        if let base { try? FileManager.default.removeItem(at: base) }
        super.tearDown()
    }

    private func environment(_ name: String) throws -> String {
        try XCTUnwrap(ProcessInfo.processInfo.environment[name], "The runner must pass \(name)")
    }

    private func get(_ path: String) async throws -> (Int, [String: Any]) {
        var login = URLRequest(url: URL(string: Self.server + "/login")!)
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.setValue("true", forHTTPHeaderField: "x-return-tokens")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["username": "qa-other", "password": "qa-other-pass"])
        let (body, _) = try await URLSession.shared.data(for: login)
        let token = try XCTUnwrap(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["user"] as? [String: Any])?["accessToken"] as? String)
        var request = URLRequest(url: URL(string: Self.server + path)!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    private func storedSession(_ id: String, item: String) async throws -> [String: Any]? {
        let (_, body) = try await get("/api/me/item/listening-sessions/\(item)?itemsPerPage=100&page=0")
        return (body["sessions"] as? [[String: Any]])?.first { $0["id"] as? String == id }
    }

    private func progress(_ item: String) async throws -> Double? {
        let (status, body) = try await get("/api/me/progress/" + item)
        return status == 200 ? body["currentTime"] as? Double : nil
    }

    func testPendingLegacyListeningReachesTheRealServerExactlyOnce() async throws {
        let open = try environment("ABS_RS_OPEN"), restarted = try environment("ABS_RS_RESTARTED")
        base = FileManager.default.temporaryDirectory.appendingPathComponent("real-adoption-\(UUID().uuidString)", isDirectory: true)
        let documents = base.appendingPathComponent("LegacyDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970 * 1000
        let connection = "conn-qa-other"
        var snapshot = LegacySnapshot(connections: [LegacyConnection(id: connection, index: 0, name: "QA", address: Self.server, version: "2.30.0", userId: Self.user, username: "qa-other")],
                                      activeConnectionIndex: 0)

        /// A downloaded single-file book, as the legacy app stored it.
        func downloaded(_ item: String, seconds: Double) throws {
            let path = "\(item)/01 Part.wav"
            let data = AdoptionHarness.wav(seconds: seconds, tone: 330)
            let url = documents.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            let file = LegacyLocalFile(id: "\(item)_part", filename: "01 Part.wav", path: path, mimeType: "audio/wav", size: data.count)
            snapshot.localItems.append(LegacyLocalItem(
                id: "local_\(item)", libraryItemId: item, mediaType: "book", serverConnectionConfigId: connection, serverAddress: Self.server, serverUserId: Self.user,
                title: "Title \(item)", files: [file],
                tracks: [LegacyTrack(index: 1, localFileId: file.id, title: file.filename, startOffset: 0, duration: seconds, mimeType: "audio/wav", contentUrl: "/api/items/\(item)/file/1", serverIndex: 0)],
                chapters: [LegacyChapter(id: 0, start: 0, end: seconds, title: "Chapter 1")], mediaDuration: seconds))
        }
        func session(_ id: String, item: String, streamed: Bool, listened: Double, position: Double, duration: Double) {
            snapshot.sessions.append(LegacySession(
                id: id, userId: Self.user, libraryItemId: item, localLibraryItemId: streamed ? nil : "local_\(item)", mediaType: "book", displayTitle: "Title", displayAuthor: "Author",
                duration: duration, playMethod: streamed ? 0 : 3, startedAt: now - 600_000, updatedAt: now - 2_000, timeListening: listened, currentTime: position,
                serverConnectionConfigId: connection, serverAddress: Self.server, isActiveSession: false))
        }
        func legacyProgress(_ item: String, position: Double, duration: Double, lastUpdate: Double) {
            snapshot.progress.append(LegacyProgress(id: "local_\(item)", localLibraryItemId: "local_\(item)", libraryItemId: item, serverConnectionConfigId: connection, serverAddress: Self.server,
                                                    serverUserId: Self.user, duration: duration, progress: position / duration, currentTime: position, lastUpdate: lastUpdate, startedAt: lastUpdate - 86_400_000))
        }

        // The legacy app's last update follows its last server sync, which the runner made before this test started.
        // Streamed: 15 s unsent since the last /sync of a session still open on the server.
        session(open, item: Self.salt, streamed: true, listened: 15, position: 25, duration: 60)
        // Streamed: 6 s unsent since the last /sync, then the server restarted and closed the session.
        session(restarted, item: Self.longStory, streamed: true, listened: 6, position: 11, duration: 20)
        // Downloaded: a session the server never saw, with its whole total.
        let local = "legacy-local-\(UUID().uuidString.prefix(8).lowercased())"
        try downloaded(Self.volume1, seconds: 4)
        session(local, item: Self.volume1, streamed: false, listened: 3, position: 3.5, duration: 4)
        // Legacy positions: newer than the server's (none) for volume 2; older than the server's newer 3.0 for volume 3.
        try downloaded(Self.volume2, seconds: 4)
        legacyProgress(Self.volume2, position: 2, duration: 4, lastUpdate: now - 30_000)
        try downloaded(Self.volume3, seconds: 4)
        legacyProgress(Self.volume3, position: 1, duration: 4, lastUpdate: now - 3_600_000)

        let archive = base.appendingPathComponent("Exports/export.absmigration")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LegacyArchive.write(snapshot, documents: documents, to: archive)
        let migrator = LegacyMigrator(root: base.appendingPathComponent("Native/LegacyMigration", isDirectory: true))
        let outcome = try migrator.migrate(try LegacyArchive.open(archive))

        let suite = "real-adoption-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentials()
        let api = APIClient(store: credentials, session: .shared)
        func adoption() -> NativeMigrationAdoption {
            let downloads = NativeDownloads(api: api, directory: base.appendingPathComponent("Native/NativeDownloads", isDirectory: true), configuration: .ephemeral)
            let player = ApplePlayback(api: api, progressResets: base.appendingPathComponent("Native/NativeListening/progress-resets.json"))
            let reading = ReadingStore(player: player, file: base.appendingPathComponent("Native/NativeListening/reading.json"))
            return NativeMigrationAdoption(downloads: downloads, reading: reading, api: api, defaults: defaults,
                                           directory: base.appendingPathComponent("Native/NativeMigrationAdoption", isDirectory: true), session: .shared)
        }
        let report = try await adoption().apply(outcome: outcome, migrator: migrator)
        print("ADOPTION_REPORT \(report.summary) issues=\(report.issues)")
        let volume3Before = try await progress(Self.volume3)

        try await api.login(server: Self.server, username: "qa-other", password: "qa-other-pass")
        let first = await adoption().sync()
        print("SYNC_1 acknowledged=\(first.sessionsAcknowledged) pending=\(first.sessionsPending) unconfirmed=\(first.sessionsUnconfirmed) failures=\(first.failures)")
        let openAfterFirst = try await storedSession(open, item: Self.salt)?["timeListening"] as? Double
        let restartedAfterFirst = try await storedSession(restarted, item: Self.longStory)?["timeListening"] as? Double
        let localAfterFirst = try await storedSession(local, item: Self.volume1)?["timeListening"] as? Double

        // A relaunch syncs again; nothing acknowledged may be counted twice.
        let second = await adoption().sync()
        print("SYNC_2 acknowledged=\(second.sessionsAcknowledged) pending=\(second.sessionsPending) unconfirmed=\(second.sessionsUnconfirmed) failures=\(second.failures)")
        let openStored = try await storedSession(open, item: Self.salt) ?? [:]
        let restartedStored = try await storedSession(restarted, item: Self.longStory)
        let localStored = try await storedSession(local, item: Self.volume1)
        let volume2 = try await progress(Self.volume2), volume3 = try await progress(Self.volume3)
        print("SERVER open=\(openStored["timeListening"] ?? "nil")/\(openStored["currentTime"] ?? "nil") restarted=\(restartedStored?["timeListening"] ?? "nil")/\(restartedStored?["currentTime"] ?? "nil") local=\(localStored?["timeListening"] ?? "nil")/\(localStored?["currentTime"] ?? "nil") volume2=\(volume2 ?? -1) volume3=\(volume3 ?? -1) (before \(volume3Before ?? -1))")

        XCTAssertEqual(first.sessionsAcknowledged, 3, "All three pending sessions must be accepted: \(first.failures)")
        XCTAssertEqual(second.sessionsAcknowledged + second.sessionsPending + second.sessionsUnconfirmed, 0)
        XCTAssertEqual(openAfterFirst, 25, "Open session: 10 s already reported plus the unsent 15 s")
        XCTAssertEqual(openStored["timeListening"] as? Double, 25, "…and not added again")
        XCTAssertEqual(restartedAfterFirst, 11, "Restarted session: the stored 5 s plus the unsent 6 s")
        XCTAssertEqual(restartedStored?["timeListening"] as? Double, 11)
        XCTAssertEqual(localAfterFirst, 3, "Downloaded session carries its whole total")
        XCTAssertEqual(localStored?["timeListening"] as? Double, 3)
        XCTAssertEqual(volume2 ?? 0, 2, accuracy: 0.01, "A legacy position newer than the server's is uploaded")
        XCTAssertEqual(volume3 ?? 0, 3, accuracy: 0.01, "An older legacy position never replaces the server's newer one")
    }
}
