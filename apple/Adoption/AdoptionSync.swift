import Foundation

/// Sends what `apply` queued for the signed-in account. Server contract (2.30.0):
/// `local-all` replaces a session's total, `/api/session/<id>/sync` adds to an open session, and
/// `PATCH /api/me/progress/...` overwrites progress. See `APPLE-MIGRATION-ADOPTION.md`.
extension NativeMigrationAdoption {
    enum SyncFailure: LocalizedError {
        case http(Int)
        case rejected(String)
        case accountChanged
        var errorDescription: String? {
            switch self {
            case .http(let code): return "The server returned HTTP \(code)."
            case .rejected(let reason): return reason
            case .accountChanged: return "The signed-in account changed; the rest waits for its own account."
            }
        }
    }

    /// Readies a progress reset for the media: carried-over listening is delivered first, since a
    /// later `local-all` would recreate the deleted progress. Throws while any of it is still owed
    /// to the server. Carried-over positions are retired by `retireProgress` once the reset is saved.
    func prepareProgressReset(account: AccountIdentity, itemID: String, episodeID: String?) async throws {
        _ = await sync()
        guard try await api.currentAccount() == account else { throw CancellationError() }
        let owed = try AdoptionLedger.load(ledgerURL).sessions.values.contains {
            !$0.acknowledged && $0.unconfirmed == nil && identity($0.account) == account && $0.session.libraryItemId == itemID && $0.session.episodeId == episodeID
        }
        if owed { throw SyncFailure.rejected("Carried-over listening for this title is still waiting to be sent, so its progress was kept. Try again when the server is reachable.") }
    }

    /// Retires the reset media's carried-over positions unsent; a reset's cleanup.
    func retireProgress(_ reset: ProgressResetIntent) throws {
        try updateLedger { ledger in
            for (key, record) in ledger.progress where !record.resolved && identity(record.account) == reset.account
                && record.progress.libraryItemID == reset.itemID && record.progress.episodeID == reset.episodeID {
                ledger.progress[key]?.resolved = true; ledger.progress[key]?.lastError = nil
            }
        }
    }

    /// Overlapping calls share one run, so nothing is sent twice by concurrent callers.
    func sync() async -> AdoptionSyncReport {
        if let syncTask { return await syncTask.value }
        let task = Task { await self.runSync() }
        syncTask = task
        let report = await task.value
        syncTask = nil
        return report
    }

    /// Reads the ledger, changes it and writes it back with no suspension in between, so work
    /// `apply` recorded while a sync was waiting on the network is never overwritten.
    func updateLedger(_ change: (inout AdoptionLedger) -> Void) throws {
        var ledger = try AdoptionLedger.load(ledgerURL)
        change(&ledger)
        try ledger.save(ledgerURL)
    }

    private func runSync() async -> AdoptionSyncReport {
        var report = AdoptionSyncReport()
        let identity: AccountIdentity
        do { identity = try await api.currentAccount() } catch {
            report.failures.append("Sign in to send carried-over listening: " + error.localizedDescription)
            return report
        }
        report.account = MigrationAccount(address: identity.server, userID: identity.userID)
        let ledger: AdoptionLedger
        do { ledger = try AdoptionLedger.load(ledgerURL) } catch {
            report.failures.append("Carried-over listening could not be read: " + error.localizedDescription)
            return report
        }
        func mine(_ account: MigrationAccount) -> Bool { self.identity(account) == identity }
        do {
            _ = try await api.me()
            guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }
        } catch {
            report.failures.append("The server could not be reached: " + error.localizedDescription)
            return finish(report, identity: identity)
        }

        for (key, record) in ledger.sessions.sorted(by: { $0.key < $1.key }) where mine(record.account) && !record.acknowledged && record.unconfirmed == nil {
            do {
                switch try await deliver(key, identity: identity) {
                case .nothing: continue
                case .held(let sent):
                    // Acknowledges only the payload that was checked, should the record have changed meanwhile.
                    var acknowledged = false
                    try updateLedger {
                        guard $0.sessions[key]?.session == sent, $0.sessions[key]?.acknowledged == false else { return }
                        $0.sessions[key]?.acknowledged = true; $0.sessions[key]?.lastError = nil; acknowledged = true
                    }
                    if acknowledged { report.sessionsAcknowledged += 1 }
                case .unconfirmed(let checked, let reason):
                    try updateLedger {
                        guard $0.sessions[key]?.session == checked, $0.sessions[key]?.acknowledged == false else { return }
                        $0.sessions[key]?.unconfirmed = reason; $0.sessions[key]?.lastError = nil
                    }
                    report.failures.append("Listening in \"\(record.session.displayTitle ?? record.session.libraryItemId ?? "an item")\" is kept on this device: " + reason)
                }
            } catch {
                try? updateLedger { $0.sessions[key]?.lastError = error.localizedDescription }
                report.failures.append("Listening in \"\(record.session.displayTitle ?? record.session.libraryItemId ?? "an item")\" is still waiting: " + error.localizedDescription)
                if Self.accountChanged(error) { return finish(report, identity: identity) }
            }
        }

        for (key, record) in ledger.progress.sorted(by: { $0.key < $1.key }) where mine(record.account) && !record.resolved {
            do {
                if try await sendProgress(key, identity: identity) { report.progressSent += 1 }
            } catch {
                try? updateLedger { $0.progress[key]?.lastError = error.localizedDescription }
                report.failures.append("The position in \(record.progress.libraryItemID ?? "an item") is still waiting: " + error.localizedDescription)
                if Self.accountChanged(error) { return finish(report, identity: identity) }
            }
        }

        for (key, record) in ledger.awaiting.sorted(by: { $0.key < $1.key }) where mine(record.account) && !record.resolved {
            do {
                if try await complete(key, identity: identity) { report.downloadsCompleted += 1 }
            } catch {
                try? updateLedger { $0.awaiting[key]?.lastError = error.localizedDescription }
                report.failures.append("\"\(record.title)\" is still waiting for the server: " + error.localizedDescription)
                if Self.accountChanged(error) { return finish(report, identity: identity) }
            }
        }
        return finish(report, identity: identity)
    }

    private static func accountChanged(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case SyncFailure.accountChanged = error { return true }
        return false
    }

    private func finish(_ report: AdoptionSyncReport, identity: AccountIdentity) -> AdoptionSyncReport {
        var report = report
        guard let ledger = try? AdoptionLedger.load(ledgerURL) else { return report }
        report.sessionsPending = ledger.sessions.values.filter { self.identity($0.account) == identity && !$0.acknowledged && $0.unconfirmed == nil }.count
        report.sessionsUnconfirmed = ledger.sessions.values.filter { self.identity($0.account) == identity && !$0.acknowledged && $0.unconfirmed != nil }.count
        report.progressPending = ledger.progress.values.filter { self.identity($0.account) == identity && !$0.resolved }.count
        return report
    }

    // MARK: Transport

    /// One authenticated request as `identity`. A 401 lets the API client refresh the token once.
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil, as identity: AccountIdentity, retry: Bool = true) async throws -> (Int, Data) {
        guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }
        let token = try await api.validToken()
        guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }
        var request = URLRequest(url: try ServerAddress(identity.server).url(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            // Non-finite numbers would raise an Objective-C exception in JSONSerialization.
            guard JSONSerialization.isValidJSONObject(body) else { throw SyncFailure.rejected("The saved values are not valid numbers and are kept on this device.") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw SyncFailure.http(0) }
        if status == 401 {
            guard retry else { throw APIError.signInRequired }
            _ = try await api.me()
            return try await send(method, path, query: query, body: body, as: identity, retry: false)
        }
        return (status, data)
    }

    private func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

    private var deviceID: String {
        if let stored = defaults.string(forKey: "nativeDeviceID"), !stored.isEmpty { return stored }
        let created = UUID().uuidString
        defaults.set(created, forKey: "nativeDeviceID")
        return created
    }

    // MARK: Sessions

    /// JavaScript `Date` accepts milliseconds up to 8.64e15; anything else is not a usable time.
    static func plausibleTime(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 && $0 <= 8.64e15 ? $0 : nil }
    }

    /// No `date` or `dayOfWeek`: like the legacy client, the server derives both from `updatedAt`
    /// (`objects/PlaybackSession.js` in 2.30), so no client calendar or time zone is involved.
    private func payload(_ session: LegacySession, account: AccountIdentity, total: Double) throws -> [String: Any] {
        guard let updated = Self.plausibleTime(session.updatedAt) ?? Self.plausibleTime(session.startedAt) else {
            throw SyncFailure.rejected("The session has no usable time and is kept on this device.")
        }
        return [
            "id": session.id, "userId": account.userID, "libraryItemId": session.libraryItemId ?? NSNull(), "episodeId": session.episodeId ?? NSNull(),
            "mediaType": session.mediaType, "displayTitle": session.displayTitle ?? "", "displayAuthor": session.displayAuthor ?? "",
            "duration": session.duration, "playMethod": session.playMethod, "mediaPlayer": "AVPlayer",
            "startedAt": Self.plausibleTime(session.startedAt) ?? updated, "updatedAt": updated,
            "timeListening": total, "currentTime": session.currentTime,
            "chapters": session.chapters.map { ["id": $0.id, "start": $0.start, "end": $0.end, "title": $0.title ?? ""] as [String: Any] },
        ]
    }

    /// `local-all` with this exact total; succeeds only when the server accepted this session.
    private func sendLocal(_ session: LegacySession, total: Double, identity: AccountIdentity) async throws {
        let body: [String: Any] = ["sessions": [try payload(session, account: identity, total: total)],
                                   "deviceInfo": ["deviceId": deviceID, "clientName": "Audiobookshelf Native", "manufacturer": "Apple", "model": "iPhone / iPad"]]
        let (status, data) = try await send("POST", "api/session/local-all", body: body, as: identity)
        guard status == 200 else { throw SyncFailure.http(status) }
        let results = json(data)["results"] as? [[String: Any]] ?? []
        guard let result = results.first(where: { $0["id"] as? String == session.id }) else { throw SyncFailure.rejected("The server did not confirm this session.") }
        guard result["success"] as? Bool == true else { throw SyncFailure.rejected((result["error"] as? String) ?? "The server did not accept this session.") }
    }

    /// Pages through the server's sessions of the session's item until `stop` returns true.
    private func scanStored(_ session: LegacySession, identity: AccountIdentity, stop: ([String: Any]) -> Bool) async throws {
        guard let item = session.libraryItemId else { throw SyncFailure.rejected("The session names no item.") }
        let path = "api/me/item/listening-sessions/\(item)" + (session.episodeId.map { "/" + $0 } ?? "")
        var page = 0
        while true {
            let (status, data) = try await send("GET", path, query: [URLQueryItem(name: "itemsPerPage", value: "50"), URLQueryItem(name: "page", value: String(page))], as: identity)
            guard status == 200 else { throw SyncFailure.http(status) }
            let value = json(data)
            for row in value["sessions"] as? [[String: Any]] ?? [] where stop(row) { return }
            page += 1
            if page >= (value["numPages"] as? Int ?? 0) { return }
        }
    }

    /// The server's row for a closed session; total 0 when it has none.
    private func storedRow(_ session: LegacySession, identity: AccountIdentity) async throws -> AdoptionLedger.StoredRow {
        var stored = AdoptionLedger.StoredRow(timeListening: 0)
        try await scanStored(session, identity: identity) { row in
            guard row["id"] as? String == session.id else { return false }
            stored = AdoptionLedger.StoredRow(timeListening: (row["timeListening"] as? Double) ?? 0, currentTime: row["currentTime"] as? Double, updatedAt: row["updatedAt"] as? Double)
            return true
        }
        return stored
    }

    /// The server's row for a downloaded session, if it has one. The legacy app posted
    /// `play_local_` sessions while they were open; 2.30 stores each under an id of its own
    /// choosing, keeping the session's `startedAt` (`PlaybackSessionManager.syncLocalSession`).
    /// A row under the session's own id comes from an earlier attempt here. More than one
    /// candidate is not guessed between.
    private func earlierPost(of session: LegacySession, identity: AccountIdentity) async throws -> [String: Any]? {
        let started = Self.plausibleTime(session.startedAt)
        var own: [String: Any]?
        var candidates: [[String: Any]] = []
        try await scanStored(session, identity: identity) { row in
            guard let id = row["id"] as? String else { return false }
            if id == session.id { own = row; return true }
            if let started, row["startedAt"] as? Double == started { candidates.append(row) }
            return false
        }
        if let own { return own }
        guard candidates.count <= 1 else { throw SyncFailure.rejected("The server has more than one session that could be this one, so it is kept on this device.") }
        return candidates.first
    }

    enum Delivery {
        /// Nothing needed sending.
        case nothing
        /// The server holds exactly this session's listening.
        case held(LegacySession)
        /// The server may or may not hold it; it is kept and not sent again.
        case unconfirmed(LegacySession, String)
    }

    /// Errors after which the request certainly did not reach the server.
    private static func notSent(_ error: Error) -> Bool {
        if error is SyncFailure || error is APIError { return true }
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .badURL, .unsupportedURL, .secureConnectionFailed].contains(error.code)
    }

    /// Sends one session so that the server holds its listening exactly once, and never replaces
    /// listening the server has that this device does not know about.
    private func deliver(_ key: String, identity: AccountIdentity) async throws -> Delivery {
        guard let record = try AdoptionLedger.load(ledgerURL).sessions[key], !record.acknowledged, record.unconfirmed == nil else { return .nothing }
        let session = record.session
        if record.semantics == .sessionTotal {
            var target = session
            if record.checkEarlierPost == true, let row = try await earlierPost(of: session, identity: identity) {
                let total = (row["timeListening"] as? Double) ?? 0, updated = (row["updatedAt"] as? Double) ?? 0
                if total == session.timeListening, row["currentTime"] as? Double == session.currentTime, updated <= (session.updatedAt ?? 0) { return .held(session) }
                if total > session.timeListening || updated > (session.updatedAt ?? 0) {
                    return .unconfirmed(session, "The server already has this session with more or later listening, which was not replaced.")
                }
                target.id = (row["id"] as? String) ?? session.id
            }
            // Its whole total replaces the server's row, which has less of it.
            try await sendLocal(target, total: session.timeListening, identity: identity)
            return .held(session)
        }

        let delta = session.timeListening.isFinite ? max(session.timeListening, 0) : 0
        guard delta > 0 else { return .nothing }
        if record.syncAttempted == true {
            return .unconfirmed(session, "An earlier attempt to add this listening got no answer, so the server may already have it. It is not sent again.")
        }
        if let before = record.storedRow, let issued = record.issuedTotal {
            // `local-all` replaces the row's total, position and time unconditionally, so it is
            // sent again only while the row is exactly as read, or exactly as sent.
            let sent = AdoptionLedger.StoredRow(timeListening: issued, currentTime: session.currentTime, updatedAt: session.updatedAt)
            let stored = try await storedRow(session, identity: identity)
            guard stored == before || stored == sent else {
                return .unconfirmed(session, "The server's row for this session changed since it was read, so it was not replaced.")
            }
            try await sendLocal(session, total: issued, identity: identity)
            return .held(session)
        }

        let (status, _) = try await send("GET", "api/session/\(session.id)", as: identity)
        if status == 200 {
            // The server's position as it is now; a newer one is not rewound.
            var remote: RemoteProgress?
            if let item = session.libraryItemId { remote = try await remoteProgress(item, episode: session.episodeId, identity: identity) }
            let position = remote.flatMap { $0.lastUpdate > (session.updatedAt ?? 0) ? $0.currentTime : nil } ?? session.currentTime
            // `/sync` adds; its total cannot show whose listening it holds, so only its answer counts.
            try updateLedger { $0.sessions[key]?.syncAttempted = true }
            let synced: Int
            do {
                (synced, _) = try await send("POST", "api/session/\(session.id)/sync", body: ["currentTime": position, "timeListened": delta, "duration": session.duration], as: identity)
            } catch {
                if Self.notSent(error) { try updateLedger { $0.sessions[key]?.syncAttempted = nil }; throw error }
                return .unconfirmed(session, "The server did not answer while this listening was being added, so it may already have it. It is not sent again.")
            }
            if synced == 200 { return .held(session) }
            if synced == 404 {
                // Not open after all: nothing was added, so the closed-session path applies next.
                try updateLedger { $0.sessions[key]?.syncAttempted = nil }
                throw SyncFailure.http(synced)
            }
            return .unconfirmed(session, "The server answered HTTP \(synced) while this listening was being added, so it may already have it. It is not sent again.")
        }
        guard status == 404 else { throw SyncFailure.http(status) }
        let stored = try await storedRow(session, identity: identity)
        if let updated = stored.updatedAt, updated > (session.updatedAt ?? 0) {
            return .unconfirmed(session, "The server's row for this session was written after the legacy app's last update, so it was not replaced.")
        }
        try updateLedger { $0.sessions[key]?.storedRow = stored; $0.sessions[key]?.issuedTotal = stored.timeListening + delta }
        try await sendLocal(session, total: stored.timeListening + delta, identity: identity)
        return .held(session)
    }

    // MARK: Progress

    private struct RemoteProgress {
        var currentTime: Double
        var isFinished: Bool
        var lastUpdate: Double
    }

    private static func progressPath(_ item: String, episode: String?) -> String {
        "api/me/progress/\(item)" + (episode.map { "/" + $0 } ?? "")
    }

    /// The server's progress for an item as it is now; nil when it has none.
    private func remoteProgress(_ item: String, episode: String?, identity: AccountIdentity) async throws -> RemoteProgress? {
        let (status, data) = try await send("GET", Self.progressPath(item, episode: episode), as: identity)
        if status == 404 { return nil }
        guard status == 200 else { throw SyncFailure.http(status) }
        let value = json(data)
        return RemoteProgress(currentTime: (value["currentTime"] as? Double) ?? 0, isFinished: (value["isFinished"] as? Bool) ?? false, lastUpdate: (value["lastUpdate"] as? Double) ?? 0)
    }

    /// Sends a legacy position the server does not have newer, compared with the server's
    /// progress right before each change; true when sent.
    private func sendProgress(_ key: String, identity: AccountIdentity) async throws -> Bool {
        guard let record = try AdoptionLedger.load(ledgerURL).progress[key], !record.resolved, let item = record.progress.libraryItemID else { return false }
        // An unfinished reset retires this position when it finishes.
        guard !reading.player.progressResetPending(account: identity, itemID: item, episodeID: record.progress.episodeID) else { return false }
        let local = record.progress
        guard Self.plausibleTime(local.lastUpdate) != nil else { throw SyncFailure.rejected("The position has no usable time and is kept on this device.") }
        let path = Self.progressPath(item, episode: local.episodeID)
        func superseded(_ remote: RemoteProgress?) throws -> Bool {
            guard let remote, remote.lastUpdate >= local.lastUpdate else { return false }
            try updateLedger { if $0.progress[key]?.progress == local { $0.progress[key]?.resolved = true; $0.progress[key]?.lastError = nil } }
            return true
        }
        let remote = try await remoteProgress(item, episode: local.episodeID, identity: identity)
        if try superseded(remote) { return false }
        if remote?.isFinished == true, !local.isFinished {
            // The server keeps a finished item finished, and un-finishing resets its position
            // (`MediaProgress.applyProgressUpdate`). Stamped just before the legacy row, the
            // reset never looks newer than it, so a retry after a failure still sends it, while
            // listening anywhere after the reset is newer and wins.
            let (status, _) = try await send("PATCH", path, body: ["isFinished": false, "lastUpdate": local.lastUpdate - 1], as: identity)
            guard (200...299).contains(status) else { throw SyncFailure.http(status) }
            if try superseded(try await remoteProgress(item, episode: local.episodeID, identity: identity)) { return false }
        }
        var body: [String: Any] = ["currentTime": local.currentTime, "duration": local.duration, "progress": local.progress, "isFinished": local.isFinished,
                                   "lastUpdate": local.lastUpdate, "startedAt": local.startedAt]
        if let finished = local.finishedAt { body["finishedAt"] = finished }
        let (status, _) = try await send("PATCH", path, body: body, as: identity)
        guard (200...299).contains(status) else { throw SyncFailure.http(status) }
        try updateLedger {
            guard $0.progress[key]?.progress == local else { return }
            $0.progress[key]?.resolved = true; $0.progress[key]?.sent = true; $0.progress[key]?.lastError = nil
        }
        return true
    }

    // MARK: Downloads that needed the server

    /// Publishes a staged download once the server's item identifies its files; true when a
    /// native entry was added.
    private func complete(_ key: String, identity: AccountIdentity) async throws -> Bool {
        guard let record = try AdoptionLedger.load(ledgerURL).awaiting[key], !record.resolved else { return false }
        guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }
        let item = try await api.item(id: record.libraryItemID)
        guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }
        let staged = awaitingRoot.appendingPathComponent(record.entryID)

        var entry: NativeDownloads.Entry
        var sources: [(part: Int, file: AdoptionLedger.AwaitingRecord.File)] = []
        switch record.kind {
        case .supplementary:
            guard let file = record.files.first,
                  let library = item.supplementaryEbooks.first(where: { $0.metadata?.filename == file.filename }),
                  let ebook = library.ebook, ["pdf", "epub"].contains(ebook.format)
            else { throw SyncFailure.rejected("The server no longer lists this file for the item.") }
            let media = ListeningMedia(itemID: item.id, episodeID: nil, title: file.filename, author: item.author, mediaType: item.mediaType, duration: 0, startTime: 0)
            entry = NativeDownloads.Entry(id: record.entryID, account: identity, media: media, tracks: [], chapters: [], ebook: ebook, supplementaryID: library.ino,
                                          serverPosition: 0, serverUpdatedAt: 0, generation: UUID().uuidString, finished: [], state: .failed, error: nil)
            sources = [(0, file)]
        case .interrupted:
            let episode = record.episodeID.flatMap { id in item.media.episodes?.first { $0.id == id } }
            guard record.episodeID == nil || episode != nil else { throw SyncFailure.rejected("The server no longer has this episode.") }
            let tracks = episode.map { $0.audioTrack.map { [$0] } ?? [] } ?? item.media.tracks ?? []
            guard tracks.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.startOffset.isFinite && $0.startOffset >= 0 }) else { throw SyncFailure.rejected("The server's copy has no playable audio.") }
            let ebookFile = record.files.first { $0.role == .ebook }
            let ebook = episode == nil ? item.media.ebookFile.flatMap { ["pdf", "epub"].contains($0.format) && $0.metadata?.filename == ebookFile?.filename ? $0 : nil } : nil
            for file in record.files where file.role != .ebook {
                if let index = tracks.firstIndex(where: { $0.metadata?.filename == file.filename }), !sources.contains(where: { $0.part == index }) { sources.append((index, file)) }
            }
            if let ebook, let ebookFile, ebook.metadata?.filename == ebookFile.filename { sources.append((tracks.count, ebookFile)) }
            guard !sources.isEmpty else { throw SyncFailure.rejected("The server's copy no longer has the parts that had finished.") }
            let length = episode?.duration ?? item.media.duration ?? tracks.map { $0.startOffset + $0.duration }.max() ?? 0
            let media = ListeningMedia(itemID: item.id, episodeID: record.episodeID, title: episode?.title ?? item.title, author: item.author, mediaType: item.mediaType,
                                       duration: length.isFinite && length >= 0 ? length : 0, startTime: record.serverPosition)
            entry = NativeDownloads.Entry(id: record.entryID, account: identity, media: media, tracks: tracks, chapters: episode?.chapters ?? item.media.chapters ?? [], ebook: ebook,
                                          serverPosition: record.serverPosition, serverUpdatedAt: record.serverUpdatedAt, generation: UUID().uuidString, finished: [], state: .failed, error: nil)
        }

        func resolve(_ reason: AdoptionReport.Download.Status?) throws {
            try updateLedger {
                $0.awaiting[key]?.resolved = true
                // A resolved record without an error means the entry was added here, even if the
                // user removed it since.
                $0.awaiting[key]?.lastError = reason == .keptNative ? "This app already had its own download." : nil
            }
            try? FileManager.default.removeItem(at: staged)
        }
        if let reason = blocked(entry) {
            try resolve(reason)
            return false
        }
        entry.finished = sources.map(\.part).sorted()
        entry.state = entry.finished.count == entry.parts.count ? .ready : .failed
        entry.error = entry.state == .ready ? nil : "\(entry.finished.count) of \(entry.parts.count) parts were carried over. Retry the download to fetch the rest; the carried-over parts are kept."

        // Read and stage the files off the main actor.
        let staging = stagingRoot.appendingPathComponent("sync", isDirectory: true)
        let hook = beforePlacing, entryID = entry.id
        let plan = sources.map { (part: $0.part, file: $0.file, source: staged.appendingPathComponent($0.file.staged), target: downloads.adoptionFile(entry, part: $0.part)) }
        defer { try? FileManager.default.removeItem(at: staging) }
        let moves = try await Task.detached(priority: .userInitiated) { () throws -> [AdoptionFiles.Move] in
            try? FileManager.default.removeItem(at: staging)
            return try plan.map { item in
                let expected = AdoptionFiles.Stamp(of: item.target)
                hook?(item.target)
                let path = staging.appendingPathComponent("\(entryID)-\(item.part)")
                try AdoptionFiles.place(item.source, sha256: item.file.sha256, confirmed: item.file.stamp, at: path)
                return AdoptionFiles.Move(staged: path, target: item.target, expected: expected)
            }
        }.value
        guard try await api.currentAccount() == identity else { throw SyncFailure.accountChanged }

        // From here to the manifest write nothing suspends, so the store and the paths are as
        // checked when the files move into place.
        guard downloads.account == identity else { throw SyncFailure.accountChanged }
        if let reason = blocked(entry) {
            try resolve(reason)
            return false
        }
        guard moves.allSatisfy(\.targetUnchanged) else { throw SyncFailure.rejected("Something else wrote where this download goes; it is tried again later.") }
        do {
            for move in moves { try move.finish() }
            try downloads.publishAdopted([(entry, nil)])
        } catch {
            if !downloads.entries.contains(where: { $0.id == entry.id }) { try? FileManager.default.removeItem(at: downloads.root.appendingPathComponent(entry.id)) }
            throw error
        }
        try resolve(nil)
        return true
    }
}
