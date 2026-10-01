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
    private let source: LegacySource
    private let connections: [String: (LegacyConnection, MigrationAccount)]
    private(set) var accounts: [MigratedAccount] = []
    private(set) var files: [String: PlannedFile] = [:]
    private(set) var issues: [MigrationIssue] = []
    private var unsafePaths: Set<String> = []
    private var rejectedPaths: Set<String> = []

    init(source: LegacySource) {
        self.source = source
        let snapshot = source.snapshot
        var connections: [String: (LegacyConnection, MigrationAccount)] = [:]
        var issues: [MigrationIssue] = []
        for connection in snapshot.connections.sorted(by: { $0.index < $1.index }) {
            guard let account = MigrationAccount(address: connection.address, userID: connection.userId) else {
                issues.append(MigrationIssue(code: .unreadableConnection, account: nil, libraryItemID: nil, legacyPath: nil,
                                             message: "The saved server \"\(connection.name)\" has an address or user that can no longer be used. Add the server again to sign in."))
                continue
            }
            connections[connection.id] = (connection, account)
        }
        self.connections = connections
        self.issues = issues
        buildAccounts()
        planFiles()
        planInterruptedDownloads()
    }

    // MARK: Accounts

    private func account(connectionID: String?, address: String?, userID: String?) -> MigrationAccount? {
        if let id = connectionID, let known = connections[id] { return known.1 }
        guard let address = address, let userID = userID else { return nil }
        return MigrationAccount(address: address, userID: userID)
    }

    private func account(for item: LegacyLocalItem) -> MigrationAccount? {
        account(connectionID: item.serverConnectionConfigId, address: item.serverAddress, userID: item.serverUserId)
    }

    private mutating func buildAccounts() {
        let snapshot = source.snapshot
        var byAccount: [MigrationAccount: MigratedAccount] = [:]
        for (connection, account) in connections.values.sorted(by: { $0.0.index < $1.0.index }) {
            let active = connection.index == snapshot.activeConnectionIndex
            if var existing = byAccount[account] {
                existing.legacyConnectionIDs.append(connection.id)
                if active {
                    existing.wasActive = true
                    existing.name = connection.name
                    existing.username = connection.username
                    existing.serverVersion = connection.version
                }
                byAccount[account] = existing
            } else {
                byAccount[account] = MigratedAccount(account: account, name: connection.name, username: connection.username, serverVersion: connection.version,
                                                     legacyConnectionIDs: [connection.id], wasActive: active, credentials: .reauthenticationRequired)
            }
        }
        let referenced = snapshot.localItems.map { account(for: $0) }
            + snapshot.progress.map { account(connectionID: $0.serverConnectionConfigId, address: $0.serverAddress, userID: $0.serverUserId) }
            + snapshot.sessions.map { account(connectionID: $0.serverConnectionConfigId, address: $0.serverAddress, userID: $0.userId) }
            + snapshot.pendingDownloads.map { account(connectionID: $0.serverConnectionConfigId, address: $0.serverAddress, userID: $0.serverUserId) }
        for case let account? in referenced where byAccount[account] == nil {
            byAccount[account] = MigratedAccount(account: account, name: account.server, username: "", serverVersion: "", legacyConnectionIDs: [], wasActive: false, credentials: .reauthenticationRequired)
        }
        accounts = byAccount.values.sorted { $0.account < $1.account }
    }

    /// The secret of the account's active connection if it has one, else of its first connection.
    func secret(for account: MigratedAccount, from source: LegacySource) -> LegacyAccountSecret? {
        guard let secrets = source.secrets else { return nil }
        let candidates = account.legacyConnectionIDs.compactMap { connections[$0]?.0 }
            .sorted { ($0.index == source.snapshot.activeConnectionIndex ? 0 : 1, $0.index) < ($1.index == source.snapshot.activeConnectionIndex ? 0 : 1, $1.index) }
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
        return String(SHA256.hash(data: Data("\(account.server)\n\(account.userID)".utf8)).hex.prefix(24))
    }

    /// Resolves a legacy relative path inside the source root, or nil when it would escape it.
    private func resolve(_ path: String) -> URL? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        let base = source.filesRoot.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/") else { return nil }
        return url
    }

    private mutating func planFiles() {
        for item in source.snapshot.localItems {
            let account = account(for: item)
            if account == nil {
                report(.unscopedData, account: nil, item: item.libraryItemId ?? item.id, path: nil,
                       "\"\(item.title)\" was downloaded without a recorded server account. Its files are kept on this device; sign in to the server it came from to link them again.")
            }
            let itemDirectory = item.id.replacingOccurrences(of: "/", with: "_")
            var references = item.files.map { (path: $0.path, id: $0.id, filename: $0.filename, mime: $0.mimeType, size: $0.size) }
            if let cover = item.coverPath { references.append((cover, "cover", (cover as NSString).lastPathComponent, nil, 0)) }
            for reference in references where files[Self.fileKey(account, reference.path)] == nil {
                guard let url = resolve(reference.path) else {
                    report(.unsafePath, account: account, item: item.libraryItemId, path: reference.path,
                           "A file reference of \"\(item.title)\" points outside the app's downloads and was not read.")
                    unsafePaths.insert(reference.path)
                    continue
                }
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let actualSize = (attributes[.size] as? NSNumber)?.int64Value else {
                    report(.fileMissing, account: account, item: item.libraryItemId, path: reference.path,
                           "A downloaded file of \"\(item.title)\" is no longer on this device. Download it again when you need it; the rest of the item is kept.")
                    rejectedPaths.insert(reference.path)
                    continue
                }
                if source.recordedDigests[reference.path] != nil, reference.size > 0, actualSize != Int64(reference.size) {
                    report(.fileCorrupt, account: account, item: item.libraryItemId, path: reference.path,
                           "This downloaded file was damaged in the export. The original in the old app is unchanged; export again or download it again.")
                    rejectedPaths.insert(reference.path)
                    continue
                }
                if reference.size > 0 && actualSize != Int64(reference.size) {
                    report(.fileIncomplete, account: account, item: item.libraryItemId, path: reference.path,
                           "A downloaded file of \"\(item.title)\" is incomplete (\(actualSize) of \(reference.size) bytes). The original is kept; download it again to play this part offline.")
                    rejectedPaths.insert(reference.path)
                    continue
                }
                let relative = reference.path.split(separator: "/").dropFirst().joined(separator: "/")
                files[Self.fileKey(account, reference.path)] = PlannedFile(
                    legacyPath: reference.path, source: url,
                    destination: "\(Self.directory(for: account))/\(itemDirectory)/\(relative.isEmpty ? reference.path : relative)",
                    legacyFileID: reference.id, filename: reference.filename, mimeType: reference.mime, size: actualSize,
                    account: account, libraryItemID: item.libraryItemId
                )
            }
            for track in item.tracks + item.episodes.compactMap(\.track) where track.localFileId != nil && !item.files.contains(where: { $0.id == track.localFileId }) {
                report(.fileMissing, account: account, item: item.libraryItemId, path: nil,
                       "\"\(item.title)\" lists an audio part whose file record is missing. Download it again to play that part offline.")
            }
        }
    }

    private mutating func planInterruptedDownloads() {
        for download in source.snapshot.pendingDownloads {
            let owner = account(connectionID: download.serverConnectionConfigId, address: download.serverAddress, userID: download.serverUserId)
            report(.downloadInterrupted, account: owner, item: download.libraryItemId, path: nil,
                   "The download of \"\(download.title ?? download.libraryItemId ?? "an item")\" was not finished before the upgrade (\(download.completedParts) of \(download.totalParts) parts). Start it again from the item.")
        }
    }

    mutating func report(_ code: MigrationIssue.Code, account: MigrationAccount?, item: String?, path: String?, _ message: String) {
        let issue = MigrationIssue(code: code, account: account, libraryItemID: item, legacyPath: path, message: message)
        if !issues.contains(issue) { issues.append(issue) }
    }

    // MARK: Outcome

    mutating func outcome(kind: LegacySourceKind, fingerprint: String, accounts: [MigratedAccount], adopted: [String: MigratedFile]) -> MigrationOutcome {
        let snapshot = source.snapshot
        var downloads: [MigratedDownload] = []
        for item in snapshot.localItems {
            let owner = account(for: item)
            let filesByID = Dictionary(item.files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var complete = true
            func file(_ id: String?) -> MigratedFile? {
                guard let id = id, let legacy = filesByID[id], let migrated = adopted[Self.fileKey(owner, legacy.path)] else {
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
            let referenced = Set(item.tracks.compactMap(\.localFileId) + item.episodes.compactMap { $0.track?.localFileId } + [item.ebook?.localFileId].compactMap { $0 })
            for legacy in item.files where !referenced.contains(legacy.id) && adopted[Self.fileKey(owner, legacy.path)] == nil {
                complete = false
            }
            let cover = item.coverPath.flatMap { adopted[Self.fileKey(owner, $0)] }
            downloads.append(MigratedDownload(account: owner, legacyLocalItemID: item.id, libraryItemID: item.libraryItemId, mediaType: item.mediaType,
                                              title: item.title, author: item.author, cover: cover, tracks: tracks, chapters: item.chapters,
                                              ebook: ebook, episodes: episodes, complete: complete))
        }

        let itemsByID = Dictionary(snapshot.localItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var progress: [MigratedProgress] = []
        for entry in snapshot.progress {
            let owner = account(connectionID: entry.serverConnectionConfigId, address: entry.serverAddress, userID: entry.serverUserId)
            let reading = entry.ebookLocation.map { Self.readingLocation($0, format: itemsByID[entry.localLibraryItemId]?.ebook?.format, fraction: entry.ebookProgress) }
            if owner == nil {
                report(.unscopedData, account: nil, item: entry.libraryItemId ?? entry.localLibraryItemId, path: nil,
                       "The saved progress of \"\(itemsByID[entry.localLibraryItemId]?.title ?? entry.libraryItemId ?? entry.id)\" has no recorded server account. It is kept on this device but cannot be sent to a server.")
            }
            if reading?.kind == .invalid {
                report(.invalidReadingLocation, account: owner, item: entry.libraryItemId, path: nil,
                       "The saved reading position of \"\(itemsByID[entry.localLibraryItemId]?.title ?? entry.libraryItemId ?? entry.id)\" could not be interpreted. It is kept unchanged; the book opens at the start until you read on.")
            }
            progress.append(MigratedProgress(account: owner, legacyID: entry.id, legacyLocalItemID: entry.localLibraryItemId, libraryItemID: entry.libraryItemId,
                                             episodeID: entry.episodeId ?? entry.localEpisodeId, duration: entry.duration, progress: entry.progress,
                                             currentTime: entry.currentTime, isFinished: entry.isFinished, lastUpdate: entry.lastUpdate,
                                             startedAt: entry.startedAt, finishedAt: entry.finishedAt, reading: reading))
        }

        var sessions: [MigratedSession] = []
        for session in snapshot.sessions {
            var owner = account(connectionID: session.serverConnectionConfigId, address: session.serverAddress, userID: session.userId)
            if let id = session.serverConnectionConfigId, let connection = connections[id]?.0, let user = session.userId, user != connection.userId {
                report(.accountMismatch, account: nil, item: session.libraryItemId, path: nil,
                       "Unsent listening for \"\(session.displayTitle ?? session.libraryItemId ?? "an item")\" belongs to a different user than its saved server. It is kept but not sent to either account.")
                owner = nil
            } else if owner == nil {
                report(.unscopedData, account: nil, item: session.libraryItemId, path: nil,
                       "Unsent listening for \"\(session.displayTitle ?? session.libraryItemId ?? "an item")\" has no recorded server account. It is kept on this device but cannot be sent to a server.")
            }
            sessions.append(MigratedSession(account: owner, session: session, semantics: session.localLibraryItemId == nil ? .sinceLastSync : .sessionTotal))
        }

        let settings = MigratedSettings(device: snapshot.deviceSettings, player: snapshot.playerSettings,
                                        preferences: LegacyStorageAllowlist.preferences(snapshot.preferences),
                                        webStorage: LegacyStorageAllowlist.webStorage(snapshot.webStorage))
        return MigrationOutcome(formatVersion: MigrationOutcome.formatVersion, sourceKind: kind, sourceFingerprint: fingerprint,
                                legacySchemaVersion: snapshot.schemaVersion, accounts: accounts, settings: settings, downloads: downloads,
                                progress: progress, pendingSessions: sessions, issues: issues)
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
