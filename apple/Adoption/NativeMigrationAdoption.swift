import Foundation

/// The durable steps of `apply`, in order. `planRecorded`: the ledger records what is about to be
/// placed, and the queued listening; no file has moved yet. `filesPublished`: every staged file
/// is in place. `manifestWritten`: the
/// native manifest has the adopted entries and their provenance; `ledgerWritten`: the ledger no
/// longer records entries the store refused.
enum AdoptionStep: String, CaseIterable {
    case planRecorded, filesPublished, manifestWritten, ledgerWritten, settingsWritten, readingWritten
}

/// How far the file work of a running `apply` is.
struct AdoptionProgress: Equatable {
    var completed: Int
    var total: Int
}

/// Carries a committed legacy migration into the native stores and sends its unsent listening.
///
/// Native entries carried over get identifiers derived from the migrated artifact, so a repeated
/// or interrupted `apply` finds its own work again and never duplicates it; anything the user made
/// in this app for the same item wins.
///
/// `apply` reads, checks and stages files off the main actor. Back on the main actor, with no
/// suspension in between, it checks that each native entry and path is still as it was when staged,
/// moves the staged files into place and publishes; calls run one at a time. A `sync()` may run
/// meanwhile: both change the ledger only by reading, changing and writing it with no suspension in
/// between.
@MainActor final class NativeMigrationAdoption {
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeMigrationAdoption", isDirectory: true)
    }

    let downloads: NativeDownloads
    let reading: ReadingStore
    let api: APIClient
    let defaults: UserDefaults
    let root: URL
    let session: URLSession
    /// Called after each durable step of `apply`; throwing simulates the app stopping there.
    var interruption: ((AdoptionStep) throws -> Void)?
    /// Called with the native path a migrated file is about to be placed at.
    var beforePlacing: ((URL) -> Void)?
    /// Called on the main actor as `apply` gets through its file work.
    var onProgress: ((AdoptionProgress) -> Void)?
    var syncTask: Task<AdoptionSyncReport, Never>?
    private var applying: Task<Void, Never>?

    var ledgerURL: URL { root.appendingPathComponent("ledger.json") }
    var awaitingRoot: URL { root.appendingPathComponent("Awaiting", isDirectory: true) }
    /// Files are staged here, on the volume of the native stores, until they are moved into place.
    var stagingRoot: URL { root.appendingPathComponent("Staging", isDirectory: true) }

    init(downloads: NativeDownloads, reading: ReadingStore, api: APIClient, defaults: UserDefaults = .standard, directory: URL = NativeMigrationAdoption.directory, session: URLSession = .shared) {
        self.downloads = downloads
        self.reading = reading
        self.api = api
        self.defaults = defaults
        root = directory
        self.session = session
        reading.player.registerProgressResetCleanup("carried-over") { [weak self] in try self?.retireProgress($0) }
    }

    func identity(_ account: MigrationAccount) -> AccountIdentity? { try? AccountIdentity(server: account.server, userID: account.userID) }

    /// One carried-over download: its native entry and, per part, the migrated file if any.
    private struct Plan {
        let entry: NativeDownloads.Entry
        let account: MigrationAccount
        let files: [MigratedFile?]
    }

    /// File work for one native entry, prepared on the main actor and done off it.
    private struct EntryJob {
        let entry: NativeDownloads.Entry
        /// The entry as the native store had it, when it already exists.
        let existing: NativeDownloads.Entry?
        let record: AdoptionLedger.EntryRecord?
        let files: [Int: MigratedFile]
        let targets: [Int: URL]
        var row: AdoptionReport.Download
    }

    private struct EntryResult {
        /// Parts finished once `moves` are in place.
        var finished: [Int]
        var record: AdoptionLedger.EntryRecord
        var moves: [Int: AdoptionFiles.Move] = [:]
        /// Parts whose current file is intact; they stay finished if their move fails.
        var intact: Set<Int> = []
        var failure: String?
    }

    /// Files a download that waits for the server keeps under `Awaiting/<entryID>`.
    private struct StageJob {
        struct Source {
            let role: LegacyDownloadPart.Role
            let filename: String
            let staged: String
            let file: MigratedFile
        }
        var record: AdoptionLedger.AwaitingRecord
        let sources: [Source]
        let previous: [AdoptionLedger.AwaitingRecord.File]
        let directory: URL
        var row: AdoptionReport.Download
    }

    private struct StageResult {
        var files: [AdoptionLedger.AwaitingRecord.File]
        var failure: String?
    }

    /// A migrated file the migrator confirmed, with the stamp it had right after.
    private struct Source {
        let url: URL
        let sha256: String
        let stamp: AdoptionFiles.Stamp
    }

    /// Carries `outcome` over. Calls run one at a time, in order.
    func apply(outcome: MigrationOutcome, migrator: LegacyMigrator) async throws -> AdoptionReport {
        let previous = applying
        let task = Task { @MainActor in
            _ = await previous?.value
            return try await self.runApply(outcome: outcome, migrator: migrator)
        }
        applying = Task { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func runApply(outcome: MigrationOutcome, migrator: LegacyMigrator) async throws -> AdoptionReport {
        let ledger = try AdoptionLedger.load(ledgerURL)
        var report = AdoptionReport()
        report.moduleIssues = outcome.issues
        report.signedInAccount = downloads.account.flatMap { MigrationAccount(address: $0.server, userID: $0.userID) }
        report.accountsRequiringSignIn = outcome.accounts.filter { $0.credentials == .reauthenticationRequired && identity($0.account) != downloads.account }

        // Plan on the main actor, against the native stores as they are now.
        var slots: [AdoptionReport.Download?] = []
        var entryJobs: [(slot: Int, job: EntryJob)] = []
        var stageJobs: [(slot: Int, job: StageJob)] = []
        for download in outcome.downloads {
            for plan in plans(for: download, outcome: outcome, slots: &slots) {
                switch classify(plan, ledger: ledger) {
                case .done(let row): slots.append(row)
                case .work(let job): entryJobs.append((slots.count, job)); slots.append(nil)
                }
            }
            for item in stageSupplementary(download, ledger: ledger) {
                switch item {
                case .done(let row): slots.append(row)
                case .work(let job): stageJobs.append((slots.count, job)); slots.append(nil)
                }
            }
        }
        for download in outcome.interruptedDownloads {
            switch stageInterrupted(download, outcome: outcome, ledger: ledger) {
            case .done(let row): slots.append(row)
            case .work(let job): stageJobs.append((slots.count, job)); slots.append(nil)
            }
        }

        // Read, check and stage files off the main actor; nothing here touches a store or a
        // native path.
        let roots = [downloads.root, awaitingRoot]
        let staging = stagingRoot.appendingPathComponent("apply", isDirectory: true)
        let hook = beforePlacing
        let total = entryJobs.count + stageJobs.count
        let entryWork = entryJobs.map(\.job), stageWork = stageJobs.map(\.job)
        let worker = Task.detached(priority: .userInitiated) { () async throws -> ([EntryResult], [StageResult]) in
            try await Self.prepare(entryWork, stageWork, roots: roots, staging: staging, migrator: migrator, hook: hook) { done in
                await self.onProgress?(AdoptionProgress(completed: done, total: total))
            }
        }
        let (entryResults, stageResults) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        defer { try? FileManager.default.removeItem(at: staging) }

        // Back on the main actor, with no suspension from here to the manifest write: what the
        // user or the native app did meanwhile wins.
        var decided: [(slot: Int, job: EntryJob, row: AdoptionReport.Download, finished: [Int], moves: [Int: AdoptionFiles.Move], intact: Set<Int>, failure: String?)] = []
        var records: [String: AdoptionLedger.EntryRecord] = [:]
        for ((slot, job), result) in zip(entryJobs, entryResults) {
            var row = job.row
            if let existing = job.existing {
                guard let current = downloads.entries.first(where: { $0.id == existing.id }) else {
                    row.nativeEntryID = nil
                    row.adoptedParts = 0
                    row.status = .removedByUser
                    row.message = "Removed in this app while it was carried over; it is not added again."
                    slots[slot] = row
                    continue
                }
                guard current.generation == existing.generation, current.state == existing.state, current.finished == existing.finished else {
                    row.adoptedParts = current.finished.count
                    row.status = status(of: current)
                    row.message = "This app changed it meanwhile; it was left as it is."
                    slots[slot] = row
                    continue
                }
            } else if let reason = blocked(job.entry) {
                row.status = reason
                row.message = reason == .removedByUser ? "Removed in this app after it was carried over; it is not added again." : "This app already has its own download of it, which was kept."
                slots[slot] = row
                continue
            }
            var finished = result.finished, record = result.record, moves = result.moves
            for (index, move) in result.moves where !move.targetUnchanged {
                // Something else wrote this path meanwhile; that file is not adoption's to replace.
                moves[index] = nil
                record.parts[String(index)] = nil
                record.stamps[String(index)] = nil
                record.pending?[String(index)] = nil
                if job.existing == nil || !FileManager.default.fileExists(atPath: move.target.path) { finished.removeAll { $0 == index } }
            }
            if job.existing != nil || !finished.isEmpty { records[job.entry.id] = record }
            decided.append((slot, job, row, finished, moves, result.intact, result.failure))
        }
        var awaiting: [String: AdoptionLedger.AwaitingRecord] = [:]
        for ((slot, job), result) in zip(stageJobs, stageResults) {
            guard !result.files.isEmpty else {
                var row = job.row
                row.status = .unavailable
                row.message = (job.record.kind == .supplementary ? "\(row.supplementaryFile ?? "This file") could not be carried over" : "None of its finished parts could be carried over")
                    + (result.failure.map { " (\($0))" } ?? "") + ". Download it again from the item."
                slots[slot] = row
                continue
            }
            var record = job.record
            record.files = result.files
            awaiting[record.entryID] = record
            slots[slot] = awaitingRow(record, supplementaryFile: job.row.supplementaryFile, total: job.row.totalParts)
        }

        // What is about to be published, and the listening owed, are recorded first.
        try updateLedger { ledger in
            for (id, record) in records { ledger.entries[id] = record }
            for (id, record) in awaiting where ledger.awaiting[id]?.resolved != true { ledger.awaiting[id] = record }
            queueListening(outcome, ledger: &ledger)
        }
        report.unsendableSessions = unsendable(outcome)
        try interruption?(.planRecorded)

        var changes: [(entry: NativeDownloads.Entry, previous: NativeDownloads.Entry?)] = []
        for item in decided {
            var row = item.row, finished = item.finished
            for (index, move) in item.moves.sorted(by: { $0.key < $1.key }) {
                let key = String(index)
                do {
                    try move.finish()
                    if let placed = records[item.job.entry.id]?.pending?[key] {
                        records[item.job.entry.id]?.parts[key] = placed.sha256
                        records[item.job.entry.id]?.stamps[key] = placed.stamp
                    }
                } catch {
                    // A part that was missing or damaged stays so; only an intact one stays finished.
                    if !item.intact.contains(index) { finished.removeAll { $0 == index } }
                }
                records[item.job.entry.id]?.pending?[key] = nil
            }
            if records[item.job.entry.id]?.pending?.isEmpty == true { records[item.job.entry.id]?.pending = nil }
            defer { slots[item.slot] = row }
            if let existing = item.job.existing {
                var next = existing
                if Set(finished) != Set(existing.finished) {
                    next.finished = finished.sorted()
                    next.state = next.finished.count == existing.parts.count ? .ready : .failed
                    next.error = next.state == .ready ? nil : Self.partialMessage(next.finished.count, of: existing.parts.count)
                    changes.append((next, existing))
                }
                row.adoptedParts = next.finished.count
                row.status = status(of: next)
                if row.status == .partial { row.message = next.error ?? Self.partialMessage(next.finished.count, of: next.parts.count) }
                continue
            }
            guard !finished.isEmpty else {
                try? FileManager.default.removeItem(at: downloads.root.appendingPathComponent(item.job.entry.id, isDirectory: true))
                row.status = .unavailable
                row.message = "None of its files could be carried over" + (item.failure.map { " (\($0))" } ?? "") + ". The originals are kept; download it again."
                continue
            }
            var entry = item.job.entry
            entry.finished = finished.sorted()
            entry.state = entry.finished.count == entry.parts.count ? .ready : .failed
            entry.error = entry.state == .ready ? nil : Self.partialMessage(entry.finished.count, of: entry.parts.count)
            changes.append((entry, nil))
            row.nativeEntryID = entry.id
            row.adoptedParts = entry.finished.count
            row.status = status(of: entry)
            row.message = entry.error
        }
        try interruption?(.filesPublished)

        var rejected: [String: Error] = [:]
        if !changes.isEmpty {
            do { try downloads.publishAdopted(changes) } catch {
                // One entry the store refuses does not hold back the others.
                for change in changes {
                    do { try downloads.publishAdopted([change]) } catch { rejected[change.entry.id] = error }
                }
            }
        }
        try interruption?(.manifestWritten)
        for change in changes {
            guard let error = rejected[change.entry.id], let slot = slots.firstIndex(where: { $0?.nativeEntryID == change.entry.id }), var row = slots[slot] else { continue }
            if let current = downloads.entries.first(where: { $0.id == change.entry.id }) {
                row.adoptedParts = current.finished.count
                row.status = status(of: current)
                row.message = "This app changed it meanwhile; it was left as it is."
            } else {
                if change.previous == nil { try? FileManager.default.removeItem(at: downloads.root.appendingPathComponent(change.entry.id, isDirectory: true)) }
                row.nativeEntryID = nil
                row.adoptedParts = 0
                row.status = error is CancellationError ? .keptNative : .unavailable
                row.message = error is CancellationError ? "This app already has its own download of it, which was kept."
                    : "It could not be added to Downloads (\(error.localizedDescription)). The originals are kept; download it again."
            }
            slots[slot] = row
        }
        // The ledger now names the files that moved, and drops entries the store refused.
        let unpublished = Set(changes.filter { $0.previous == nil && rejected[$0.entry.id] != nil }.map(\.entry.id))
        try updateLedger { ledger in
            for (id, record) in records { ledger.entries[id] = unpublished.contains(id) ? nil : record }
        }
        report.downloads.append(contentsOf: slots.compactMap { $0 })
        try interruption?(.ledgerWritten)

        report.settings = applySettings(outcome.settings)
        try interruption?(.settingsWritten)
        try adoptReading(outcome, report: &report)
        try interruption?(.readingWritten)
        report.listening = listeningSummary(try AdoptionLedger.load(ledgerURL))
        return report
    }

    // MARK: File work

    /// Checks and repairs the files of every job, staging what native entries need under
    /// `staging`. Runs off the main actor and writes only files adoption owns: never a migrated
    /// source, never a native path.
    nonisolated private static func prepare(_ entries: [EntryJob], _ stages: [StageJob], roots: [URL], staging: URL, migrator: LegacyMigrator, hook: ((URL) -> Void)?,
                                            progress: (Int) async -> Void) async throws -> ([EntryResult], [StageResult]) {
        for root in roots { AdoptionFiles.removeLeftovers(under: root) }
        try? FileManager.default.removeItem(at: staging)
        func source(_ file: MigratedFile?) -> Source? {
            guard let file, let url = try? migrator.fileURL(for: file), let stamp = AdoptionFiles.Stamp(of: url), stamp.size > 0 else { return nil }
            return Source(url: url, sha256: file.sha256, stamp: stamp)
        }
        var done = 0
        var entryResults: [EntryResult] = []
        for job in entries {
            try Task.checkCancellation()
            var available: [Int: Source] = [:]
            for (index, file) in job.files { available[index] = source(file) }
            var result = EntryResult(finished: job.existing?.finished ?? [], record: job.record ?? AdoptionLedger.EntryRecord())
            func adopt(_ index: Int) -> Bool {
                guard let found = available[index], let target = job.targets[index] else { return false }
                let expected = AdoptionFiles.Stamp(of: target)
                hook?(target)
                let staged = staging.appendingPathComponent("\(job.entry.id)-\(index)")
                do {
                    let stamp = try AdoptionFiles.place(found.url, sha256: found.sha256, confirmed: found.stamp, at: staged)
                    result.record.pending = (result.record.pending ?? [:]).merging([String(index): .init(sha256: found.sha256, stamp: stamp)]) { $1 }
                    result.moves[index] = AdoptionFiles.Move(staged: staged, target: target, expected: expected)
                    return true
                } catch {
                    result.failure = error.localizedDescription
                    return false
                }
            }
            if let existing = job.existing {
                for index in existing.finished.sorted() {
                    let key = String(index)
                    // Without a record the entry was published by an apply that stopped before
                    // writing it; its parts came from these same migrated files.
                    guard let target = job.targets[index] else { continue }
                    // A stop after a staged file moved but before the ledger named it.
                    if let moved = result.record.pending?[key], let current = AdoptionFiles.Stamp(of: target), current.isSameFile(as: moved.stamp) {
                        result.record.parts[key] = moved.sha256
                        result.record.stamps[key] = moved.stamp
                    }
                    result.record.pending?[key] = nil
                    guard let recorded = result.record.parts[key] ?? (job.record == nil ? available[index]?.sha256 : nil) else { continue }
                    switch AdoptionFiles.ownership(of: target, stamp: result.record.stamps[key], sha256: recorded) {
                    case .replaced:
                        // The native app wrote this part itself; it is no longer adoption's.
                        result.record.parts[key] = nil
                        result.record.stamps[key] = nil
                    case .intact:
                        result.record.parts[key] = recorded
                        result.record.stamps[key] = AdoptionFiles.Stamp(of: target)
                        result.intact.insert(index)
                        if let found = available[index], found.sha256 != recorded { _ = adopt(index) }
                    case .missing, .damaged:
                        if !adopt(index) {
                            result.finished.removeAll { $0 == index }
                            result.record.parts[key] = nil
                            result.record.stamps[key] = nil
                        }
                    }
                }
            }
            for index in job.targets.keys.sorted() where !result.finished.contains(index) {
                if adopt(index) { result.finished.append(index) }
            }
            if result.record.pending?.isEmpty == true { result.record.pending = nil }
            entryResults.append(result)
            done += 1
            await progress(done)
        }

        var stageResults: [StageResult] = []
        for job in stages {
            try Task.checkCancellation()
            var result = StageResult(files: [])
            for item in job.sources {
                let target = job.directory.appendingPathComponent(item.staged)
                if var kept = job.previous.first(where: { $0.role == item.role && $0.filename == item.filename && $0.staged == item.staged && $0.sha256 == item.file.sha256 }),
                   AdoptionFiles.ownership(of: target, stamp: kept.stamp, sha256: kept.sha256) == .intact {
                    kept.stamp = AdoptionFiles.Stamp(of: target)
                    result.files.append(kept)
                    continue
                }
                guard let found = source(item.file) else { continue }
                do {
                    // Only adoption writes under `Awaiting`, so these are placed directly.
                    hook?(target)
                    let stamp = try AdoptionFiles.place(found.url, sha256: found.sha256, confirmed: found.stamp, at: target)
                    result.files.append(AdoptionLedger.AwaitingRecord.File(role: item.role, filename: item.filename, staged: item.staged, sha256: found.sha256, stamp: stamp))
                } catch {
                    result.failure = error.localizedDescription
                }
            }
            stageResults.append(result)
            done += 1
            await progress(done)
        }
        return (entryResults, stageResults)
    }

    // MARK: Downloads

    private func row(_ download: MigratedDownload, episodeID: String? = nil, title: String? = nil, status: AdoptionReport.Download.Status, adopted: Int = 0, total: Int = 0, message: String?) -> AdoptionReport.Download {
        AdoptionReport.Download(account: download.account, libraryItemID: download.libraryItemID, episodeID: episodeID, supplementaryFile: nil, title: title ?? download.title,
                                status: status, nativeEntryID: nil, adoptedParts: adopted, totalParts: total, message: message)
    }

    private func progress(_ outcome: MigrationOutcome, account: MigrationAccount, itemID: String, episodeID: String?, localItem: String?) -> MigratedProgress? {
        let candidates = outcome.progress.filter { $0.account == account && $0.libraryItemID == itemID && $0.episodeID == episodeID }
        return candidates.first { $0.legacyLocalItemID == localItem } ?? candidates.first
    }

    private func audioTrack(_ track: MigratedTrack, legacy: LegacyTrack?, files: [LegacyLocalFile]) -> AudioTrack {
        let filename = track.file?.filename ?? files.first { $0.id == legacy?.localFileId }?.filename ?? track.title
        let ext = filename.map { ($0 as NSString).pathExtension.lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
        // A recorded URL never carries its query (older builds put the token there).
        let path = legacy?.contentUrl.map { String($0.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]) } ?? ""
        return AudioTrack(contentUrl: path, mimeType: track.mimeType, metadata: .init(filename: filename, ext: ext), startOffset: track.startOffset, duration: track.duration)
    }

    private func chapters(_ chapters: [LegacyChapter]) -> [Chapter] {
        chapters.map { Chapter(id: $0.id, title: $0.title ?? "Chapter \($0.id + 1)", start: $0.start, end: $0.end) }
    }

    /// The native entries a migrated item becomes: one per book, one per podcast episode.
    private func plans(for download: MigratedDownload, outcome: MigrationOutcome, slots: inout [AdoptionReport.Download?]) -> [Plan] {
        guard let account = download.account, let itemID = download.libraryItemID, let identity = identity(account) else {
            slots.append(row(download, status: .unattached, message: "Kept on this device. It is not linked to a server account, so it is not added to Downloads."))
            return []
        }
        let legacy = download.legacyItem
        func entry(id: String, episodeID: String?, title: String, tracks: [AudioTrack], chapters: [Chapter], ebook: EbookFile?, duration: Double?) -> NativeDownloads.Entry {
            let position = progress(outcome, account: account, itemID: itemID, episodeID: episodeID, localItem: download.legacyLocalItemID)
            let ends = tracks.map { $0.startOffset + $0.duration }.max() ?? 0
            let length = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? ends
            let media = ListeningMedia(itemID: itemID, episodeID: episodeID, title: title, author: download.author ?? "", mediaType: download.mediaType, duration: length, startTime: position?.currentTime ?? 0)
            return NativeDownloads.Entry(id: id, account: identity, media: media, tracks: tracks, chapters: chapters, ebook: ebook, serverPosition: position?.currentTime ?? 0,
                                         serverUpdatedAt: position?.lastUpdate ?? 0, generation: AdoptionFiles.stableID("generation", id), finished: [], state: .failed, error: nil)
        }

        if download.mediaType == "podcast" {
            return download.episodes.compactMap { episode in
                guard let track = episode.track else { return nil }
                let id = AdoptionFiles.stableID("download", account.server, account.userID, download.legacyLocalItemID, episode.id)
                let legacyTrack = legacy.episodes.first { $0.id == episode.id }?.track
                var audio = audioTrack(track, legacy: legacyTrack, files: legacy.files)
                audio = AudioTrack(contentUrl: audio.contentUrl, mimeType: audio.mimeType, metadata: audio.metadata, startOffset: 0, duration: audio.duration)
                return Plan(entry: entry(id: id, episodeID: episode.id, title: episode.title, tracks: [audio], chapters: chapters(episode.chapters), ebook: nil, duration: episode.duration ?? track.duration),
                            account: account, files: [track.file])
            }
        }

        var tracks: [AudioTrack] = []
        var files: [MigratedFile?] = []
        for (position, track) in download.tracks.enumerated() {
            tracks.append(audioTrack(track, legacy: position < legacy.tracks.count ? legacy.tracks[position] : nil, files: legacy.files))
            files.append(track.file)
        }
        var ebook: EbookFile?
        if let book = download.ebook {
            if ["pdf", "epub"].contains(book.format) {
                ebook = EbookFile(ino: book.ino, ebookFormat: book.format, metadata: .init(filename: legacy.ebook?.filename ?? book.file?.filename, ext: book.format))
                files.append(book.file)
            } else {
                slots.append(row(download, status: .deferredFormat, adopted: book.file == nil ? 0 : 1, total: 1,
                                            message: "\(book.format.uppercased()) books open in a later version of this app. The file is kept on this device."))
            }
        }
        guard !tracks.isEmpty || ebook != nil else {
            if download.ebook == nil { slots.append(row(download, status: .unavailable, message: "Nothing playable or readable was recorded for it. Download it again.")) }
            return []
        }
        let id = AdoptionFiles.stableID("download", account.server, account.userID, download.legacyLocalItemID, "")
        return [Plan(entry: entry(id: id, episodeID: nil, title: download.title, tracks: tracks, chapters: chapters(download.chapters), ebook: ebook, duration: legacy.mediaDuration),
                     account: account, files: files)]
    }

    private static func partialMessage(_ finished: Int, of total: Int) -> String {
        "\(finished) of \(total) parts were carried over. Retry the download to fetch the rest; the carried-over parts are kept."
    }

    private func status(of entry: NativeDownloads.Entry) -> AdoptionReport.Download.Status {
        switch entry.state {
        case .queued: return .inProgress
        case .ready: return .ready
        case .failed, .cancelled: return .partial
        }
    }

    private enum Planned<Job> {
        case done(AdoptionReport.Download)
        case work(Job)
    }

    /// What a planned entry needs, decided against the native store and the ledger as they are.
    private func classify(_ plan: Plan, ledger: AdoptionLedger) -> Planned<EntryJob> {
        let planned = plan.entry
        var row = AdoptionReport.Download(account: plan.account, libraryItemID: planned.media.libraryItemID, episodeID: planned.media.episodeID, supplementaryFile: nil,
                                          title: planned.media.title, status: .unavailable, nativeEntryID: nil, adoptedParts: 0, totalParts: plan.files.count, message: nil)
        var files: [Int: MigratedFile] = [:]
        for (index, file) in plan.files.enumerated() { files[index] = file }
        let record = ledger.entries[planned.id]

        if let existing = downloads.entries.first(where: { $0.id == planned.id }) {
            row.nativeEntryID = existing.id
            row.totalParts = existing.parts.count
            row.adoptedParts = existing.finished.count
            guard existing.state != .queued else {
                row.status = .inProgress
                row.message = "This app is downloading it now; it was left to finish."
                return .done(row)
            }
            let targets = Dictionary(uniqueKeysWithValues: existing.parts.map { ($0, downloads.adoptionFile(existing, part: $0)) })
            return .work(EntryJob(entry: existing, existing: existing, record: record, files: files, targets: targets, row: row))
        }
        if let reason = blocked(planned) {
            row.status = reason
            row.message = reason == .removedByUser ? "Removed in this app after it was carried over; it is not added again." : "This app already has its own download of it, which was kept."
            return .done(row)
        }
        guard !files.isEmpty else {
            row.status = .unavailable
            row.message = "None of its files could be carried over. Download it again."
            return .done(row)
        }
        let targets = Dictionary(uniqueKeysWithValues: planned.parts.map { ($0, downloads.adoptionFile(planned, part: $0)) })
        return .work(EntryJob(entry: planned, existing: nil, record: nil, files: files, targets: targets, row: row))
    }

    /// Why a new entry must not be added: the native app has one for the same item, or the user
    /// removed it after an earlier import published it.
    func blocked(_ entry: NativeDownloads.Entry) -> AdoptionReport.Download.Status? {
        if downloads.entries.contains(where: { $0.id == entry.id || ($0.account == entry.account && $0.media.libraryItemID == entry.media.libraryItemID && $0.media.episodeID == entry.media.episodeID && $0.supplementaryID == entry.supplementaryID) }) {
            return .keptNative
        }
        return downloads.adoptedIDs.contains(entry.id) ? .removedByUser : nil
    }

    // MARK: Downloads that need the server

    private func awaitingRow(_ record: AdoptionLedger.AwaitingRecord, supplementaryFile: String?, total: Int) -> AdoptionReport.Download {
        var row = AdoptionReport.Download(account: record.account, libraryItemID: record.libraryItemID, episodeID: record.episodeID, supplementaryFile: supplementaryFile,
                                          title: record.title, status: .waitingForServer, nativeEntryID: nil, adoptedParts: record.files.count, totalParts: total,
                                          message: "Waiting to be matched with the server's copy. It is added to Downloads once \(record.account.server) is reachable with this account signed in.")
        guard record.resolved else {
            if let error = record.lastError { row.message = (row.message ?? "") + " Last attempt: " + error }
            return row
        }
        row.message = nil
        if let entry = downloads.entries.first(where: { $0.id == record.entryID }) {
            row.nativeEntryID = entry.id
            row.adoptedParts = entry.finished.count
            row.totalParts = entry.parts.count
            row.status = status(of: entry)
            if row.status == .partial { row.message = entry.error }
        } else if record.lastError == nil {
            row.status = .removedByUser
            row.message = "Removed in this app after it was carried over; it is not added again."
        } else {
            row.status = .keptNative
            row.message = "This app already has its own download of it, which was kept."
        }
        return row
    }

    /// The name a staged file gets: its position, keeping a plausible extension.
    private static func stagedName(_ index: Int, _ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return "\(index)" + (ext.isEmpty || ext.count > 10 ? "" : "." + ext)
    }

    private func stageSupplementary(_ download: MigratedDownload, ledger: AdoptionLedger) -> [Planned<StageJob>] {
        var result: [Planned<StageJob>] = []
        for file in download.files where file.role == .supplementary {
            let filename = file.filename ?? (file.legacyPath as NSString).lastPathComponent
            let format = (filename as NSString).pathExtension.lowercased()
            var row = AdoptionReport.Download(account: download.account, libraryItemID: download.libraryItemID, episodeID: nil, supplementaryFile: filename, title: download.title,
                                              status: .deferredFormat, nativeEntryID: nil, adoptedParts: file.file == nil ? 0 : 1, totalParts: 1, message: nil)
            guard ["pdf", "epub"].contains(format) else {
                row.message = "\(filename) is kept on this device; this app does not open its format yet."
                result.append(.done(row))
                continue
            }
            guard let account = download.account, let itemID = download.libraryItemID, identity(account) != nil else {
                row.status = .unattached
                row.message = "\(filename) is kept on this device but not linked to a server account."
                result.append(.done(row))
                continue
            }
            let entryID = AdoptionFiles.stableID("supplementary", account.server, account.userID, download.legacyLocalItemID, file.legacyFileID)
            let previous = ledger.awaiting[entryID]
            if let previous, previous.resolved {
                result.append(.done(awaitingRow(previous, supplementaryFile: filename, total: 1)))
                continue
            }
            guard let migrated = file.file else {
                row.status = .unavailable
                row.message = "\(filename) could not be carried over. Download it again from the item."
                result.append(.done(row))
                continue
            }
            let record = AdoptionLedger.AwaitingRecord(kind: .supplementary, account: account, libraryItemID: itemID, episodeID: nil, title: download.title, entryID: entryID,
                                                       files: [], serverPosition: 0, serverUpdatedAt: 0, lastError: previous?.lastError)
            result.append(.work(StageJob(record: record, sources: [.init(role: .ebook, filename: filename, staged: Self.stagedName(0, filename), file: migrated)],
                                         previous: previous?.files ?? [], directory: awaitingRoot.appendingPathComponent(entryID), row: row)))
        }
        return result
    }

    private func stageInterrupted(_ download: MigratedInterruptedDownload, outcome: MigrationOutcome, ledger: AdoptionLedger) -> Planned<StageJob> {
        let title = download.title ?? download.libraryItemID ?? "Unfinished download"
        var row = AdoptionReport.Download(account: download.account, libraryItemID: download.libraryItemID, episodeID: download.episodeID, supplementaryFile: nil, title: title,
                                          status: .unattached, nativeEntryID: nil, adoptedParts: download.parts.filter { $0.file != nil }.count, totalParts: download.parts.count, message: nil)
        guard let account = download.account, let itemID = download.libraryItemID, identity(account) != nil else {
            row.message = "Its finished parts are kept on this device but not linked to a server account."
            return .done(row)
        }
        let entryID = AdoptionFiles.stableID("interrupted", account.server, account.userID, download.legacyDownloadID)
        let previous = ledger.awaiting[entryID]
        if let previous, previous.resolved { return .done(awaitingRow(previous, supplementaryFile: nil, total: download.parts.count)) }
        var sources: [StageJob.Source] = []
        for part in download.parts {
            guard let file = part.file else { continue }
            let filename = part.part.filename ?? file.filename ?? (file.legacyPath as NSString).lastPathComponent
            sources.append(.init(role: part.part.role, filename: filename, staged: Self.stagedName(sources.count, filename), file: file))
        }
        guard !sources.isEmpty else {
            row.status = .unavailable
            row.message = "Nothing of it had finished downloading. Start the download again from the item."
            return .done(row)
        }
        let position = progress(outcome, account: account, itemID: itemID, episodeID: download.episodeID, localItem: nil)
        let record = AdoptionLedger.AwaitingRecord(kind: .interrupted, account: account, libraryItemID: itemID, episodeID: download.episodeID, title: title, entryID: entryID, files: [],
                                                   serverPosition: position?.currentTime ?? 0, serverUpdatedAt: position?.lastUpdate ?? 0, lastError: previous?.lastError)
        return .work(StageJob(record: record, sources: sources, previous: previous?.files ?? [], directory: awaitingRoot.appendingPathComponent(entryID), row: row))
    }

    // MARK: Reading

    private func adoptReading(_ outcome: MigrationOutcome, report: inout AdoptionReport) throws {
        // The newest legacy row of a book is adopted; older ones find it there and are kept.
        for progress in outcome.progress.sorted(by: { $0.lastUpdate > $1.lastUpdate }) {
            guard let location = progress.reading else { continue }
            var row = AdoptionReport.Reading(account: progress.account, libraryItemID: progress.libraryItemID, format: location.format, location: location.raw, status: .adopted)
            defer { report.reading.append(row) }
            guard let account = progress.account, let itemID = progress.libraryItemID, let identity = identity(account) else { row.status = .unattached; continue }
            let value: String
            switch (location.kind, location.format) {
            case (.invalid, _): row.status = .invalid; continue
            case (.page, "pdf"): guard let page = location.page else { row.status = .invalid; continue }; value = String(page)
            case (.cfi, "epub"): value = location.raw
            default: row.status = .deferredFormat; continue
            }
            let fraction = location.fraction.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? 0
            let position = ReadingStore.Position(account: identity, itemID: itemID, format: location.format!, location: value, fraction: fraction,
                                                 updatedAt: progress.lastUpdate, revision: "legacy:" + progress.legacyID, pending: true, rotation: 0)
            row.location = value
            if let existing = reading.position(account: identity, itemID: itemID, format: position.format) {
                row.status = existing.revision == position.revision ? .adopted : .keptNative
            } else {
                row.status = try reading.adoptLegacy(position) ? .adopted : .keptNative
            }
        }
    }

    // MARK: Listening

    /// Legacy downloaded-media sessions use `play_local_` ids, which the server maps to a fresh id
    /// in memory only; a stable UUID keeps every retry, even across server restarts, on one row.
    static func serverSessionID(_ id: String) -> String {
        id.hasPrefix("play_local_") ? AdoptionFiles.stableID("legacy-session", id).lowercased() : id
    }

    private func queueListening(_ outcome: MigrationOutcome, ledger: inout AdoptionLedger) {
        for pending in outcome.pendingSessions {
            guard let account = pending.account else { continue }
            let key = AdoptionLedger.key(account, "session", pending.session.id)
            guard ledger.sessions[key] == nil else { continue }
            var session = pending.session
            session.id = Self.serverSessionID(session.id)
            ledger.sessions[key] = AdoptionLedger.SessionRecord(account: account, session: session, semantics: pending.semantics,
                                                                checkEarlierPost: session.id != pending.session.id ? true : nil)
        }
        for progress in outcome.progress where Self.queuesPosition(progress) {
            guard let account = progress.account, progress.libraryItemID != nil else { continue }
            let key = AdoptionLedger.key(account, "progress", progress.legacyID)
            guard ledger.progress[key] == nil else { continue }
            ledger.progress[key] = AdoptionLedger.ProgressRecord(account: account, progress: progress)
        }
    }

    private static func queuesPosition(_ progress: MigratedProgress) -> Bool { progress.reading == nil || progress.currentTime > 0 || progress.isFinished }

    /// Unsent sessions and positions with no account to send them to.
    private func unsendable(_ outcome: MigrationOutcome) -> Int {
        outcome.pendingSessions.filter { $0.account == nil }.count
            + outcome.progress.filter { Self.queuesPosition($0) && ($0.account == nil || $0.libraryItemID == nil) }.count
    }

    func listeningSummary(_ ledger: AdoptionLedger) -> [AdoptionReport.Listening] {
        var byAccount: [MigrationAccount: AdoptionReport.Listening] = [:]
        for record in ledger.sessions.values {
            var value = byAccount[record.account] ?? AdoptionReport.Listening(account: record.account, pendingSessions: 0, acknowledgedSessions: 0, pendingProgress: 0)
            if record.acknowledged { value.acknowledgedSessions += 1 } else if record.unconfirmed != nil { value.unconfirmedSessions += 1 } else { value.pendingSessions += 1 }
            byAccount[record.account] = value
        }
        for record in ledger.progress.values where !record.resolved {
            var value = byAccount[record.account] ?? AdoptionReport.Listening(account: record.account, pendingSessions: 0, acknowledgedSessions: 0, pendingProgress: 0)
            value.pendingProgress += 1
            byAccount[record.account] = value
        }
        return byAccount.values.sorted { $0.account < $1.account }
    }
}
