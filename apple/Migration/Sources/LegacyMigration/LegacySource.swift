import CryptoKit
import Foundation

/// Credentials recovered from a legacy installation. Held only in memory: not `Codable`, and every
/// textual or reflected representation is redacted so it cannot reach logs, journals or archives.
public struct LegacyAccountSecret: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accessToken: String?
    public let refreshToken: String?

    public init(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken?.isEmpty == true ? nil : accessToken
        self.refreshToken = refreshToken?.isEmpty == true ? nil : refreshToken
    }

    public var isEmpty: Bool { accessToken == nil && refreshToken == nil }
    public var description: String { "LegacyAccountSecret(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Reads a legacy connection's credentials from secure storage the current app can legitimately
/// access (only possible for an in-place upgrade with a compatible signing identity).
public protocol LegacySecretSource {
    func secret(for connection: LegacyConnection) throws -> LegacyAccountSecret?
}

/// Writes adopted credentials into the native app's secure storage.
public protocol MigrationSecretSink {
    func adopt(_ secret: LegacyAccountSecret, for account: MigratedAccount) throws
}

/// A readable legacy installation or export archive.
public struct LegacySource {
    public let kind: LegacySourceKind
    public let snapshot: LegacySnapshot
    /// Directory against which legacy relative paths resolve (Documents, or an archive's `files`).
    public let filesRoot: URL
    /// SHA-256 recorded when an archive was written, keyed by legacy relative path.
    public let recordedDigests: [String: String]
    public let secrets: LegacySecretSource?

    public init(kind: LegacySourceKind, snapshot: LegacySnapshot, filesRoot: URL, recordedDigests: [String: String] = [:], secrets: LegacySecretSource? = nil) {
        self.kind = kind
        self.snapshot = snapshot
        self.filesRoot = filesRoot
        self.recordedDigests = recordedDigests
        self.secrets = secrets
    }

    /// Content identity of the snapshot, used to recognise a retry of the same migration.
    public var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = Data(kind.rawValue.utf8) + ((try? encoder.encode(snapshot)) ?? Data())
        return SHA256.hash(data: data).hex
    }
}

extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
