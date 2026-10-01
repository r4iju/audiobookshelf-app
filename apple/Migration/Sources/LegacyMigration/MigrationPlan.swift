import CryptoKit
import Foundation

struct PlannedFile {
    let legacyPath: String
    let source: URL
    let destination: String
    let legacyFileID: String
    let filename: String?
    let mimeType: String?
    let size: Int64
    let account: MigrationAccount?
    let libraryItemID: String?

    /// Adopted files are scoped per account, so one legacy file referenced by two accounts is
    /// adopted once for each.
    var key: String { MigrationPlan.fileKey(account, legacyPath) }

    func migrated(sha256: String) -> MigratedFile {
        MigratedFile(path: destination, legacyPath: legacyPath, legacyFileID: legacyFileID, filename: filename, mimeType: mimeType, size: Int(size), sha256: sha256)
    }
}

/// Everything decidable from the snapshot and file metadata alone: account scoping, which files
/// can be adopted, reader-location interpretation and the issues to show the user. Performs no
/// writes, so it also backs the preflight.
struct MigrationPlan {
    private struct KnownConnection {
        let connection: LegacyConnection
        let account: MigrationAccount
    }

    /// Whose data a legacy row is. A row's own recorded server and user must corroborate the
    /// connection it was saved under; a connection later re-pointed at another user must not
    /// claim the earlier user's data.
    private enum Ownership {
        case owned(MigrationAccount)
        case unscoped
        case conflict
    }

    private struct FileReference {
        let path: String
        let id: String
        let filename: String?
        let mimeType: String?
        let size: Int
    }

    private let source: LegacySource
    private let connections: [String: KnownConnection]
    private(set) var accounts: [MigratedAccount] = []
    private(set) var files: [String: PlannedFile] = [:]
    private(set) var issues: [MigrationIssue] = []
    private var destinations: Set<String> = []
    private var itemOwners: [String: MigrationAccount] = [:]
    private var progressOwners: [String: MigrationAccount] = [:]
    private var sessionOwners: [String: MigrationAccount] = [:]
    private var downloadOwners: [String: MigrationAccount] = [:]

    init(source: LegacySource) {
        self.source = source
        var connections: [String: KnownConnection] = [:]
        var issues: [MigrationIssue] = []
        for connection in source.snapshot.connections.sorted(by: { $0.index < $1.index }) {
            guard let account = MigrationAccount(address: connection.address, userID: connection.userId) else {
                issues.append(MigrationIssue(code: .unreadableConnection, account: nil, libraryItemID: nil, legacyPath: nil,
                                             message: "The saved server \"\(connection.name)\" has an address or user that can no longer be used. Add the server again to sign in."))
                continue
            }
            connections[connection.id] = KnownConnection(connection: connection, account: account)
        }
        self.connections = connections
        self.issues = issues
        resolveOwners()
        buildAccounts()
        planFiles()
        planInterruptedDownloads()
    }

    // MARK: Accounts

    private func ownership(connectionID: String?, address: String?, userID: String?) -> Ownership {
        let address = address.flatMap { $0.isEmpty ? nil : $0 }
        let userID = userID.flatMap { $0.isEmpty ? nil : $0 }
        if let id = connectionID, let known = connections[id] {
            if let userID = userID, userID != known.account.userID { return .conflict }
            if let address = address, MigrationAccount(address: address, userID: known.account.userID)?.server != known.account.server { return .conflict }
            return .owned(known.account)
        }
        guard let address = address, let userID = userID, let account = MigrationAccount(address: address, userID: userID) else { return .unscoped }
        return .owned(account)
    }

    /// Resolves one row's owner, reporting why when it has none.
    private mutating func owner(connectionID: String?, address: String?, userID: String?, item: String?, unscoped: String, conflict: String) -> MigrationAccount? {
        switch ownership(connectionID: connectionID, address: address, userID: userID) {
        case .owned(let account):
            return account
        case .unscoped:
            report(.unscopedData, account: nil, item: item, path: nil, unscoped)
        case .conflict:
            report(.accountMismatch, account: nil, item: item, path: nil, conflict)
        }
        return nil
    }

    private mutating func resolveOwners() {
        let snapshot = source.snapshot
        let titles = Dictionary(snapshot.localItems.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        for item in snapshot.localItems {
            itemOwners[item.id] = owner(
                connectionID: item.serverConnectionConfigId, address: item.serverAddress, userID: item.serverUserId, item: item.libraryItemId ?? item.id,
                unscoped: "\"\(item.title)\" was downloaded without a recorded server account. Its files are kept on this device; sign in to the server it came from to link them again.",
                conflict: "\"\(item.title)\" is recorded for a different server account than the one it was saved under. Its files are kept on this device but not attached to either account.")
        }
        for entry in snapshot.progress {
            let title = titles[entry.localLibraryItemId] ?? entry.libraryItemId ?? entry.id
            progressOwners[entry.id] = owner(
                connectionID: entry.serverConnectionConfigId, address: entry.serverAddress, userID: entry.serverUserId, item: entry.libraryItemId ?? entry.localLibraryItemId,
                unscoped: "The saved progress of \"\(title)\" has no recorded server account. It is kept on this device but cannot be sent to a server.",
                conflict: "The saved progress of \"\(title)\" is recorded for a different server account than the one it was saved under. It is kept but not sent to either account.")
        }
        for session in snapshot.sessions {
            let title = session.displayTitle ?? session.libraryItemId ?? "an item"
            sessionOwners[session.id] = owner(
                connectionID: session.serverConnectionConfigId, address: session.serverAddress, userID: session.userId, item: session.libraryItemId,
                unscoped: "Unsent listening for \"\(title)\" has no recorded server account. It is kept on this device but cannot be sent to a server.",
                conflict: "Unsent listening for \"\(title)\" belongs to a different user than its saved server. It is kept but not sent to either account.")
        }
        for download in snapshot.pendingDownloads {
            let title = download.title ?? download.libraryItemId ?? "an item"
            downloadOwners[download.id] = owner(
                connectionID: download.serverConnectionConfigId, address: download.serverAddress, userID: download.serverUserId, item: download.libraryItemId,
                unscoped: "The unfinished download of \"\(title)\" has no recorded server account. Its finished parts are kept on this device.",
                conflict: "The unfinished download of \"\(title)\" is recorded for a different server account than the one it was saved under. Its finished parts are kept but not attached to either account.")
        }
    }

    private mutating func buildAccounts() {
        let snapshot = source.snapshot
        var byAccount: [MigrationAccount: MigratedAccount] = [:]
        for known in connections.values.sorted(by: { $0.connection.index < $1.connection.index }) {
            let connection = known.connection
            let active = connection.index == snapshot.activeConnectionIndex
            if var existing = byAccount[known.account] {
                existing.legacyConnectionIDs.append(connection.id)
                if active {
                    existing.wasActive = true
                    existing.name = connection.name
                    existing.username = connection.username
                    existing.serverVersion = connection.version
                }
                byAccount[known.account] = existing
            } else {
                byAccount[known.account] = MigratedAccount(account: known.account, name: connection.name, username: connection.username, serverVersion: connection.version,
                                                           legacyConnectionIDs: [connection.id], wasActive: active, credentials: .reauthenticationRequired)
            }
        }
        let referenced = Array(itemOwners.values) + Array(progressOwners.values) + Array(sessionOwners.values) + Array(downloadOwners.values)
        for account in referenced where byAccount[account] == nil {
            byAccount[account] = MigratedAccount(account: account, name: account.server, username: "", serverVersion: "", legacyConnectionIDs: [], wasActive: false, credentials: .reauthenticationRequired)
        }
        accounts = byAccount.values.sorted { $0.account < $1.account }
    }

    /// The secret of the account's active connection if it has one, else of its first connection.
    func secret(for account: MigratedAccount) -> LegacyAccountSecret? {
        guard let secrets = source.secrets else { return nil }
        let active = source.snapshot.activeConnectionIndex
        let candidates = account.legacyConnectionIDs.compactMap { connections[$0]?.connection }
            .sorted { ($0.index == active ? 0 : 1, $0.index) < ($1.index == active ? 0 : 1, $1.index) }
        for connection in candidates {
            if let secret = try? secrets.secret(for: connection), !secret.isEmpty { return secret }
        }
        return nil
    }

    // MARK: Files

    static func fileKey(_ account: MigrationAccount?, _ legacyPath: String) -> String {
        "\(directory(for: account))/\(legacyPath)"
    }

    static func directory(for account: MigrationAccount?) -> String {
        guard let account = account else { return "unscoped" }
        return digestName("\(account.server)\n\(account.userID)")
    }

    /// Legacy identifiers and paths are arbitrary strings; only their digest becomes a path
    /// component, which also keeps names differing only by case or normalisation apart on
    /// case-insensitive volumes.
    static func digestName(_ identity: String) -> String {
        String(SHA256.hash(data: Data(identity.utf8)).hex.prefix(24))
    }

    private static func isContained(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        return !relativePath.isEmpty && !relativePath.hasPrefix("/") && !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Where a legacy path is stored under an archive's `files`: its own digest directory, so
    /// paths differing only by case cannot collide on the volume the archive is written to.
    static func archivedPath(_ legacyPath: String) -> String {
        "\(digestName(legacyPath))/\((legacyPath as NSString).lastPathComponent)"
    }

    /// Resolves a legacy relative path inside the source root, or nil when it would escape it.
    private func resolve(_ path: String) -> URL? {
        let stored = source.storedPaths[path] ?? path
        guard Self.isContained(path), Self.isContained(stored) else { return nil }
        let base = source.filesRoot.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(stored).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else { return nil }
        return url
    }

    private static func coverReference(_ item: LegacyLocalItem) -> FileReference? {
        guard let cover = item.coverPath, !item.files.contains(where: { $0.path == cover }) else { return nil }
        return FileReference(path: cover, id: "cover", filename: (cover as NSString).lastPathComponent, mimeType: nil, size: 0)
    }

    private mutating func planFiles() {
        for item in source.snapshot.localItems {
            let owner = itemOwners[item.id]
            let references = item.files.map { FileReference(path: $0.path, id: $0.id, filename: $0.filename, mimeType: $0.mimeType, size: $0.size) }
                + [Self.coverReference(item)].compactMap { $0 }
            for reference in references {
                plan(reference, owner: owner, libraryItemID: item.libraryItemId, title: item.title, scope: "item\n\(item.id)")
            }
            for track in item.tracks + item.episodes.compactMap(\.track) where track.localFileId != nil && !item.files.contains(where: { $0.id == track.localFileId }) {
                report(.fileMissing, account: owner, item: item.libraryItemId, path: nil,
                       "\"\(item.title)\" lists an audio part whose file record is missing. Download it again to play that part offline.")
            }
        }
    }

    private mutating func planInterruptedDownloads() {
        for download in source.snapshot.pendingDownloads {
            let owner = downloadOwners[download.id]
            let title = download.title ?? download.libraryItemId ?? "an item"
            report(.downloadInterrupted, account: owner, item: download.libraryItemId, path: nil,
                   "The download of \"\(title)\" was not finished before the upgrade (\(download.completedParts) of \(download.totalParts) parts). Start it again from the item; finished parts are kept.")
            for part in download.parts where part.completed && part.moved {
                guard let path = part.path else { continue }
                plan(FileReference(path: path, id: part.id, filename: part.filename, mimeType: nil, size: part.size),
                     owner: owner, libraryItemID: download.libraryItemId, title: title, scope: "download\n\(download.id)")
            }
        }
    }

    /// Decides whether one legacy file can be adopted and where. The destination is
    /// `<account digest>/<owner digest>/<legacy path digest>/<file name>`, so neither an identifier
    /// nor a path can leave the account's directory or land on another file's destination.
    private mutating func plan(_ reference: FileReference, owner: MigrationAccount?, libraryItemID: String?, title: String, scope: String) {
        let key = Self.fileKey(owner, reference.path)
        guard files[key] == nil else { return }
        guard let url = resolve(reference.path) else {
            report(.unsafePath, account: owner, item: libraryItemID, path: reference.path,
                   "A file reference of \"\(title)\" points outside the app's downloads and was not read.")
            return
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let actualSize = (attributes[.size] as? NSNumber)?.int64Value else {
            report(.fileMissing, account: owner, item: libraryItemID, path: reference.path,
                   "A downloaded file of \"\(title)\" is no longer on this device. Download it again when you need it; the rest of the item is kept.")
            return
        }
        if source.recordedDigests[reference.path] != nil, reference.size > 0, actualSize != Int64(reference.size) {
            report(.fileCorrupt, account: owner, item: libraryItemID, path: reference.path, Self.damagedInExportMessage)
            return
        }
        if reference.size > 0 && actualSize != Int64(reference.size) {
            report(.fileIncomplete, account: owner, item: libraryItemID, path: reference.path,
                   "A downloaded file of \"\(title)\" is incomplete (\(actualSize) of \(reference.size) bytes). The original is kept; download it again to play this part offline.")
            return
        }
        let destination = "\(Self.directory(for: owner))/\(Self.digestName(scope))/\(Self.digestName(reference.path))/\((reference.path as NSString).lastPathComponent)"
        guard Self.isContained(destination), !destinations.contains(destination.lowercased()) else {
            report(.unsafePath, account: owner, item: libraryItemID, path: reference.path,
                   "A file of \"\(title)\" could not be given a place of its own and was not read. The original is unchanged.")
            return
        }
        destinations.insert(destination.lowercased())
        files[key] = PlannedFile(legacyPath: reference.path, source: url, destination: destination, legacyFileID: reference.id,
                                 filename: reference.filename, mimeType: reference.mimeType, size: actualSize, account: owner, libraryItemID: libraryItemID)
    }

    static let damagedInExportMessage = "This downloaded file was damaged in the export. The original in the old app is unchanged; export again or download it again."

    /// Withdraws the "missing" or "incomplete" report for a file kept from an earlier commit.
    mutating func retractUnavailable(key: String, legacyPath: String) {
        issues.removeAll { issue in
            (issue.code == .fileMissing || issue.code == .fileIncomplete) && issue.legacyPath == legacyPath && Self.fileKey(issue.account, legacyPath) == key
        }
    }

    mutating func report(_ code: MigrationIssue.Code, account: MigrationAccount?, item: String?, path: String?, _ message: String) {
        let issue = MigrationIssue(code: code, account: account, libraryItemID: item, legacyPath: path, message: message)
        if !issues.contains(issue) { issues.append(issue) }
    }

    // MARK: Outcome

    mutating func outcome(kind: LegacySourceKind, fingerprint: String, accounts: [MigratedAccount], adopted: [String: MigratedFile]) -> MigrationOutcome {
        let snapshot = source.snapshot
        let downloads = snapshot.localItems.map { download(for: $0, adopted: adopted) }
        let interrupted = snapshot.pendingDownloads.map { download -> MigratedInterruptedDownload in
            let owner = downloadOwners[download.id]
            let parts = download.parts.map { part in
                MigratedInterruptedDownload.Part(part: part, file: part.completed && part.moved ? part.path.flatMap { adopted[Self.fileKey(owner, $0)] } : nil)
            }
            return MigratedInterruptedDownload(account: owner, legacyDownloadID: download.id, libraryItemID: download.libraryItemId, episodeID: download.episodeId,
                                               title: download.title, mediaType: download.mediaType, parts: parts)
        }

        let itemsByID = Dictionary(snapshot.localItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var progress: [MigratedProgress] = []
        for entry in snapshot.progress {
            let owner = progressOwners[entry.id]
            let reading = entry.ebookLocation.map { Self.readingLocation($0, format: itemsByID[entry.localLibraryItemId]?.ebook?.format, fraction: entry.ebookProgress) }
            if reading?.kind == .invalid {
                report(.invalidReadingLocation, account: owner, item: entry.libraryItemId, path: nil,
                       "The saved reading position of \"\(itemsByID[entry.localLibraryItemId]?.title ?? entry.libraryItemId ?? entry.id)\" could not be interpreted. It is kept unchanged; the book opens at the start until you read on.")
            }
            progress.append(MigratedProgress(account: owner, legacyID: entry.id, legacyLocalItemID: entry.localLibraryItemId, libraryItemID: entry.libraryItemId,
                                             episodeID: entry.episodeId ?? entry.localEpisodeId, duration: entry.duration, progress: entry.progress,
                                             currentTime: entry.currentTime, isFinished: entry.isFinished, lastUpdate: entry.lastUpdate,
                                             startedAt: entry.startedAt, finishedAt: entry.finishedAt, reading: reading))
        }
        let sessions = snapshot.sessions.map {
            MigratedSession(account: sessionOwners[$0.id], session: $0, semantics: $0.localLibraryItemId == nil ? .sinceLastSync : .sessionTotal)
        }

        let settings = MigratedSettings(device: snapshot.deviceSettings, player: snapshot.playerSettings,
                                        preferences: LegacyStorageAllowlist.preferences(snapshot.preferences),
                                        webStorage: LegacyStorageAllowlist.webStorage(snapshot.webStorage))
        return MigrationOutcome(formatVersion: MigrationOutcome.formatVersion, sourceKind: kind, sourceFingerprint: fingerprint,
                                legacySchemaVersion: snapshot.schemaVersion, accounts: accounts, settings: settings, downloads: downloads,
                                interruptedDownloads: interrupted, progress: progress, pendingSessions: sessions, issues: issues)
    }

    private func download(for item: LegacyLocalItem, adopted: [String: MigratedFile]) -> MigratedDownload {
        let owner = itemOwners[item.id]
        func adoptedFile(_ path: String) -> MigratedFile? { adopted[Self.fileKey(owner, path)] }
        let filesByID = Dictionary(item.files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var complete = true
        func file(_ id: String?) -> MigratedFile? {
            guard let id = id, let legacy = filesByID[id], let migrated = adoptedFile(legacy.path) else {
                complete = false
                return nil
            }
            return migrated
        }
        func track(_ track: LegacyTrack, position: Int) -> MigratedTrack {
            MigratedTrack(index: track.index ?? position, file: file(track.localFileId), title: track.title, startOffset: track.startOffset, duration: track.duration, mimeType: track.mimeType)
        }
        let tracks = item.tracks.enumerated().map { track($0.element, position: $0.offset) }
        let episodes = item.episodes.map { MigratedEpisode(id: $0.id, title: $0.title, duration: $0.duration, track: $0.track.map { track($0, position: 0) }, chapters: $0.chapters) }
        let ebook = item.ebook.map { MigratedEbook(ino: $0.ino, format: $0.format.lowercased(), file: file($0.localFileId)) }

        var records = item.files.map { legacy -> MigratedItemFile in
            var record = MigratedItemFile(role: .supplementary, trackIndex: nil, episodeID: nil, legacyFileID: legacy.id, legacyPath: legacy.path,
                                          filename: legacy.filename, mimeType: legacy.mimeType, recordedSize: legacy.size, file: adoptedFile(legacy.path))
            if let position = item.tracks.firstIndex(where: { $0.localFileId == legacy.id }) {
                record.role = .track
                record.trackIndex = item.tracks[position].index ?? position
            } else if let episode = item.episodes.first(where: { $0.track?.localFileId == legacy.id }) {
                record.role = .episodeTrack
                record.episodeID = episode.id
            } else if item.ebook?.localFileId == legacy.id {
                record.role = .ebook
            } else if legacy.path == item.coverPath {
                record.role = .cover
            }
            return record
        }
        if let cover = Self.coverReference(item) {
            records.append(MigratedItemFile(role: .cover, trackIndex: nil, episodeID: nil, legacyFileID: cover.id, legacyPath: cover.path,
                                            filename: cover.filename, mimeType: nil, recordedSize: 0, file: adoptedFile(cover.path)))
        }
        if records.contains(where: { $0.file == nil }) { complete = false }

        return MigratedDownload(account: owner, legacyLocalItemID: item.id, libraryItemID: item.libraryItemId, mediaType: item.mediaType,
                                title: item.title, author: item.author, cover: item.coverPath.flatMap(adoptedFile), tracks: tracks, chapters: item.chapters,
                                ebook: ebook, episodes: episodes, files: records, legacyItem: item, complete: complete)
    }

    static func readingLocation(_ raw: String, format: String?, fraction: Double?) -> MigratedReadingLocation {
        let format = format?.lowercased()
        switch format {
        case "pdf", "cbz", "cbr":
            if let page = Int(raw), page > 0 {
                return MigratedReadingLocation(format: format, kind: .page, raw: raw, page: page, fraction: fraction)
            }
            return MigratedReadingLocation(format: format, kind: .invalid, raw: raw, page: nil, fraction: fraction)
        case "epub":
            return MigratedReadingLocation(format: format, kind: raw.hasPrefix("epubcfi(") ? .cfi : .invalid, raw: raw, page: nil, fraction: fraction)
        default:
            return MigratedReadingLocation(format: format, kind: .opaque, raw: raw, page: nil, fraction: fraction)
        }
    }
}
