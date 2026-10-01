import CryptoKit
import Foundation

/// What adoption has done so far, kept beside the native stores so `apply` and `sync` can be
/// repeated and resumed. Native stores stay the source of truth for what the user sees; the ledger
/// only records what came from the migration and what is still owed to a server.
struct AdoptionLedger: Codable {
    /// Parts adoption placed in a native entry. Whether the entry was published is the native
    /// manifest's to say (`NativeDownloads.adoptedIDs`).
    struct EntryRecord: Codable, Equatable {
        /// Content of each part adoption placed and still owns, keyed by part index.
        var parts: [String: String] = [:]
        /// The placed file of each owned part, to tell it apart from one the native app wrote.
        var stamps: [String: AdoptionFiles.Stamp] = [:]
        /// A staged file about to replace a part. Until the rename is known to have happened, both
        /// that file and the one in `stamps` are adoption's, so a stop or a failed rename never
        /// hands a damaged part to the native app.
        var pending: [String: Pending]?

        struct Pending: Codable, Equatable {
            var sha256: String
            var stamp: AdoptionFiles.Stamp
        }
    }

    struct SessionRecord: Codable {
        var account: MigrationAccount
        /// The legacy row, unchanged except for `id` (see `NativeMigrationAdoption.serverSessionID`).
        var session: LegacySession
        var semantics: MigratedSession.ListeningSemantics
        /// Open streamed session: set before its listening is added through `/sync`, cleared only
        /// when the server answered that nothing was added.
        var syncAttempted: Bool?
        /// Closed streamed session: the server's row when it was read, and the total sent through
        /// `local-all` in its place, both fixed once chosen.
        var storedRow: StoredRow?
        var issuedTotal: Double?
        var acknowledged = false
        /// Why the server may or may not hold this listening; such a session is kept and never
        /// sent again.
        var unconfirmed: String?
        /// A downloaded-media session the legacy app may have posted already, under an id the
        /// server chose; looked up before every attempt.
        var checkEarlierPost: Bool?
        var lastError: String?
    }

    /// What `local-all` replaces in a stored session row. An absent row reads as total 0.
    struct StoredRow: Codable, Equatable {
        var timeListening: Double
        var currentTime: Double?
        var updatedAt: Double?
    }

    struct ProgressRecord: Codable {
        var account: MigrationAccount
        var progress: MigratedProgress
        /// Sent, or superseded by a newer server position.
        var resolved = false
        var sent = false
        var lastError: String?
    }

    /// A download that needs the server's item before it can join the native manifest. Its
    /// adopted files are staged under `Awaiting/<entryID>` until then.
    struct AwaitingRecord: Codable {
        enum Kind: String, Codable { case supplementary, interrupted }
        struct File: Codable, Equatable {
            var role: LegacyDownloadPart.Role
            var filename: String
            var staged: String
            var sha256: String
            var stamp: AdoptionFiles.Stamp?
        }

        var kind: Kind
        var account: MigrationAccount
        var libraryItemID: String
        var episodeID: String?
        var title: String
        var entryID: String
        var files: [File]
        var serverPosition: Double
        var serverUpdatedAt: Double
        var resolved = false
        var lastError: String?
    }

    var version = 1
    var entries: [String: EntryRecord] = [:]
    var sessions: [String: SessionRecord] = [:]
    var progress: [String: ProgressRecord] = [:]
    var awaiting: [String: AwaitingRecord] = [:]

    static func load(_ url: URL) throws -> AdoptionLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return AdoptionLedger() }
        let ledger = try JSONDecoder().decode(AdoptionLedger.self, from: Data(contentsOf: url))
        guard ledger.version == 1 else { throw ListeningJournal.Failure.invalidData }
        return ledger
    }

    func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func key(_ account: MigrationAccount, _ parts: String...) -> String {
        ([account.server, account.userID] + parts).joined(separator: "\n")
    }
}

enum AdoptionFiles {
    enum Failure: LocalizedError {
        case changed
        var errorDescription: String? { "A migrated file changed while it was carried over. It was not used." }
    }

    /// A version 5 style UUID derived from `parts`, so the same migrated artifact always maps to
    /// the same native identifier, across retries and relaunches.
    static func stableID(_ parts: String...) -> String {
        let digest = Array(SHA256.hash(data: Data(parts.joined(separator: "\n").utf8)))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0f) | 0x50
        b[8] = (b[8] & 0x3f) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
    }

    /// Identity and last change of one file. A file whose stamp is unchanged since its bytes were
    /// confirmed still has those bytes; creating another name for it does not change its stamp.
    struct Stamp: Codable, Equatable {
        var device: Int64
        var inode: UInt64
        var size: Int64
        var modified: Int64

        init?(of url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
            device = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        }

        func isSameFile(as other: Stamp) -> Bool { device == other.device && inode == other.inode }
    }

    /// Whether a part adoption placed is still that file, with the bytes it placed.
    enum Ownership { case intact, damaged, missing, replaced }

    /// A different file at the path was written by the native app and is not adoption's; the same
    /// file with other bytes was damaged in place. Without a recorded stamp the bytes decide.
    static func ownership(of url: URL, stamp: Stamp?, sha256 expected: String) -> Ownership {
        guard let current = Stamp(of: url) else { return FileManager.default.fileExists(atPath: url.path) ? .replaced : .missing }
        if let stamp {
            guard current.isSameFile(as: stamp) else { return .replaced }
            if current == stamp { return .intact }
        }
        if (try? sha256(of: url)) == expected { return .intact }
        return stamp == nil ? .replaced : .damaged
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Publishes `source` at `target` as a new name for the same file when the volume allows it,
    /// else as a copy, then renames it into place atomically. Either way the placed bytes are the
    /// ones `sha256` names: a new name is trusted without reading only while the file still has
    /// the stamp it had when its bytes were confirmed. Neither the source nor any other name of it
    /// is changed; removing `target` later leaves the source intact. Returns the placed file.
    @discardableResult
    static func place(_ source: URL, sha256: String, confirmed: Stamp?, at target: URL) throws -> Stamp {
        let directory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("adopting-" + UUID().uuidString)
        do {
            if (try? FileManager.default.linkItem(at: source, to: temporary)) != nil {
                if confirmed == nil || Stamp(of: temporary) != confirmed {
                    guard try Self.sha256(of: temporary) == sha256 else { throw Failure.changed }
                }
            } else {
                try FileManager.default.copyItem(at: source, to: temporary)
                guard try Self.sha256(of: temporary) == sha256 else { throw Failure.changed }
            }
            guard let placed = Stamp(of: temporary), placed.size > 0 else { throw Failure.changed }
            guard rename(temporary.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            // rename(2) leaves both names when they already link the same file.
            if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
            return placed
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// A file placed off the main actor under a staging path, and what its native path held then.
    struct Move {
        let staged: URL
        let target: URL
        /// The target's stamp when it was staged; nil when there was no file.
        let expected: Stamp?

        /// Whether nothing changed the native path since the file was staged.
        var targetUnchanged: Bool {
            guard let expected else { return !FileManager.default.fileExists(atPath: target.path) }
            return Stamp(of: target) == expected
        }

        /// Renames the staged file into place. Called on the main actor right after
        /// `targetUnchanged`, with no suspension in between.
        func finish() throws {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard rename(staged.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }

    /// Removes temporary names an interrupted `place` left behind.
    static func removeLeftovers(under root: URL) {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("adopting-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
