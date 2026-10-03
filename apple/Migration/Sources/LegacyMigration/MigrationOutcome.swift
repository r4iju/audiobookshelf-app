import Foundation

/// How the legacy data reached this app.
public enum LegacySourceKind: String, Codable {
    /// Same bundle identifier, team and Keychain access group as the legacy app: Documents, Realm,
    /// UserDefaults and Keychain are this app's own containers.
    case inPlace
    /// A credential-free export archive the user carried across the sandbox boundary.
    case archive
}

/// The account a piece of legacy data belongs to: canonical server base plus server user ID.
/// Canonicalisation matches the native `AccountIdentity` (lowercased scheme and host, no default
/// port, no trailing slash, subpath kept).
public struct MigrationAccount: Codable, Hashable, Comparable {
    public let server: String
    public let userID: String

    public init?(address: String, userID: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty, var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil
        else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        if scheme == "https" && components.port == 443 || scheme == "http" && components.port == 80 { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let server = components.url?.absoluteString else { return nil }
        self.server = server
        self.userID = userID
    }

    public static func < (lhs: MigrationAccount, rhs: MigrationAccount) -> Bool {
        (lhs.server, lhs.userID) < (rhs.server, rhs.userID)
    }
}

public enum CredentialState: String, Codable {
    /// The legacy secret was written through `MigrationSecretSink`.
    case adopted
    /// No secret could be read (other sandbox, missing Keychain item); the user signs in again and
    /// the migrated data for this account becomes usable once the same server user is signed in.
    case reauthenticationRequired
}

public struct MigratedAccount: Codable, Equatable {
    public var account: MigrationAccount
    public var name: String
    public var username: String
    public var serverVersion: String
    public var legacyConnectionIDs: [String]
    public var wasActive: Bool
    public var credentials: CredentialState
}

public struct MigratedSettings: Codable, Equatable {
    public var device: LegacyDeviceSettings?
    public var player: LegacyPlayerSettings?
    public var preferences: [String: String]
    public var webStorage: [String: String]
}

public struct MigratedFile: Codable, Equatable {
    /// Path relative to the migration root's `Files` directory.
    public var path: String
    public var legacyPath: String
    public var legacyFileID: String
    public var filename: String?
    public var mimeType: String?
    public var size: Int
    public var sha256: String
}

public struct MigratedTrack: Codable, Equatable {
    public var index: Int
    public var file: MigratedFile?
    public var title: String?
    public var startOffset: Double
    public var duration: Double
    public var mimeType: String
}

public struct MigratedEbook: Codable, Equatable {
    public var ino: String
    public var format: String
    public var file: MigratedFile?
}

public struct MigratedEpisode: Codable, Equatable {
    public var id: String
    public var title: String
    public var duration: Double?
    public var track: MigratedTrack?
    public var chapters: [LegacyChapter]
}

/// One legacy file of a downloaded item with what it was for. Every `LocalFile` of the item is
/// listed, adopted or not, so nothing the legacy item held disappears from the outcome.
public struct MigratedItemFile: Codable, Equatable {
    public enum Role: String, Codable {
        case track, episodeTrack, ebook, cover
        /// Retained by the legacy item without a track, episode, ebook or cover pointing at it
        /// (supplementary PDFs and other kept files).
        case supplementary
    }

    public var role: Role
    public var trackIndex: Int?
    public var episodeID: String?
    public var legacyFileID: String
    public var legacyPath: String
    public var filename: String?
    public var mimeType: String?
    public var recordedSize: Int
    /// Nil when the file could not be adopted; the matching issue explains why.
    public var file: MigratedFile?
}

public struct MigratedDownload: Codable, Equatable {
    /// Nil when the legacy item recorded no resolvable account; such data is kept and reported.
    public var account: MigrationAccount?
    public var legacyLocalItemID: String
    public var libraryItemID: String?
    public var mediaType: String
    public var title: String
    public var author: String?
    public var cover: MigratedFile?
    public var tracks: [MigratedTrack]
    public var chapters: [LegacyChapter]
    public var ebook: MigratedEbook?
    public var episodes: [MigratedEpisode]
    public var files: [MigratedItemFile]
    /// The credential-free legacy record, unchanged, including metadata not interpreted here.
    public var legacyItem: LegacyLocalItem
    /// Every legacy file of the item was verified and adopted.
    public var complete: Bool
}

/// A download the upgrade interrupted. Parts that had finished are adopted so they need not be
/// downloaded again.
public struct MigratedInterruptedDownload: Codable, Equatable {
    public struct Part: Codable, Equatable {
        public var part: LegacyDownloadPart
        public var file: MigratedFile?
    }

    public var account: MigrationAccount?
    public var legacyDownloadID: String
    public var libraryItemID: String?
    public var episodeID: String?
    public var title: String?
    public var mediaType: String?
    public var parts: [Part]
}

/// A saved reader location, interpreted by format but always carrying the untouched legacy value.
public struct MigratedReadingLocation: Codable, Equatable {
    public enum Kind: String, Codable {
        /// 1-based page (PDF, CBZ, CBR).
        case page
        /// epub.js CFI.
        case cfi
        /// Location whose semantics are not interpreted by migration (MOBI, AZW3 or an
        /// unknown format); preserved verbatim for the reader.
        case opaque
        /// The stored value does not match its format; preserved verbatim and reported.
        case invalid
    }

    public var format: String?
    public var kind: Kind
    public var raw: String
    public var page: Int?
    public var fraction: Double?
}

public struct MigratedProgress: Codable, Equatable {
    public var account: MigrationAccount?
    public var legacyID: String
    public var legacyLocalItemID: String
    public var libraryItemID: String?
    public var episodeID: String?
    public var duration: Double
    public var progress: Double
    public var currentTime: Double
    public var isFinished: Bool
    public var lastUpdate: Double
    public var startedAt: Double
    public var finishedAt: Double?
    public var reading: MigratedReadingLocation?
}

public struct MigratedSession: Codable, Equatable {
    /// What the stored `timeListening` counts. Downloaded-media sessions hold the session total and
    /// were posted whole (`/api/session/local`, or `/api/session/local-all` on reconnect). Streamed
    /// sessions reset it after each acknowledged `/api/session/<id>/sync`, so it holds listening
    /// since that sync; the legacy app also sent these through `local-all` on reconnect.
    public enum ListeningSemantics: String, Codable {
        case sessionTotal
        case sinceLastSync
    }

    public var account: MigrationAccount?
    public var session: LegacySession
    public var semantics: ListeningSemantics
}

public struct MigrationIssue: Codable, Equatable, Hashable {
    public enum Code: String, Codable {
        case reauthenticationRequired
        case fileMissing
        case fileIncomplete
        case fileCorrupt
        case unsafePath
        case unscopedData
        case accountMismatch
        case invalidReadingLocation
        case unreadableConnection
        case downloadInterrupted
    }

    public var code: Code
    public var account: MigrationAccount?
    public var libraryItemID: String?
    public var legacyPath: String?
    /// Plain-language explanation shown to the user. Never contains secrets.
    public var message: String
}

/// The committed result of a migration, persisted as `outcome.json` under the migration root.
public struct MigrationOutcome: Codable, Equatable {
    public static let formatVersion = 1

    public var formatVersion: Int
    public var sourceKind: LegacySourceKind
    public var sourceFingerprint: String
    public var legacySchemaVersion: UInt64
    public var accounts: [MigratedAccount]
    public var settings: MigratedSettings
    public var downloads: [MigratedDownload]
    public var interruptedDownloads: [MigratedInterruptedDownload]
    public var progress: [MigratedProgress]
    public var pendingSessions: [MigratedSession]
    public var issues: [MigrationIssue]
}
