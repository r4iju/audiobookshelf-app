import Foundation
import LegacyMigration

/// Reads a legacy refresh token (`AudiobookshelfRefreshTokens` / `refresh_token_<connection id>`).
public protocol LegacyRefreshTokenReading {
    func refreshToken(forConnectionID id: String) -> String?
}

/// The legacy app's own container, readable only by a build with the legacy bundle identifier,
/// team and Keychain access group (an in-place upgrade).
public enum LegacyInstallation {
    public static let capacitorPreferencePrefix = "CapacitorStorage."

    /// Realm's default location in the legacy app: `Documents/default.realm`.
    public static func realmURL(documents: URL) -> URL {
        documents.appendingPathComponent("default.realm")
    }

    public static func isPresent(documents: URL) -> Bool {
        FileManager.default.fileExists(atPath: realmURL(documents: documents).path)
    }

    /// - Parameter webStorage: WebView localStorage entries if the caller could read them; they are
    ///   allowlisted, so credential entries never cross.
    public static func source(documents: URL, defaults: UserDefaults, webStorage: [String: String] = [:], refreshTokens: LegacyRefreshTokenReading?, workDirectory: URL) throws -> LegacySource {
        let contents = try LegacyRealmReader.read(realmAt: realmURL(documents: documents), workDirectory: workDirectory)
        var snapshot = contents.snapshot
        snapshot.preferences = capacitorPreferences(defaults)
        snapshot.webStorage = LegacyStorageAllowlist.webStorage(webStorage)
        return LegacySource(kind: .inPlace, snapshot: snapshot, filesRoot: documents,
                            secrets: InstallationSecrets(accessTokens: contents.secrets, refreshTokens: refreshTokens))
    }

    static func capacitorPreferences(_ defaults: UserDefaults) -> [String: String] {
        var values: [String: String] = [:]
        for key in LegacyStorageAllowlist.preferenceKeys {
            if let value = defaults.string(forKey: capacitorPreferencePrefix + key) { values[key] = value }
        }
        return values
    }
}

private struct InstallationSecrets: LegacySecretSource {
    let accessTokens: [String: LegacyAccountSecret]
    let refreshTokens: LegacyRefreshTokenReading?

    func secret(for connection: LegacyConnection) throws -> LegacyAccountSecret? {
        let secret = LegacyAccountSecret(accessToken: accessTokens[connection.id]?.accessToken,
                                         refreshToken: refreshTokens?.refreshToken(forConnectionID: connection.id))
        return secret.isEmpty ? nil : secret
    }
}

public enum LegacyExportProgress: Equatable {
    case copyingDatabase
    case readingDatabase
    case copyingFiles(LegacyArchiveProgress)
}

/// Runs inside the legacy app: writes a credential-free archive the user carries to a separately
/// identified app (such as the native preview) through the Files app.
public enum LegacyArchiveExporter {
    /// - Parameters:
    ///   - workDirectory: belongs to the exporter. It holds the database copy, which contains
    ///     access tokens, and is removed before returning or throwing; copies left by an export the
    ///     system interrupted are removed first.
    ///   - copyRealm: writes a consistent copy of the open legacy Realm to the given URL, normally
    ///     `Realm.writeCopy(toFile:)`. The copy is read, never the live database.
    ///   - webStorage: WebView `localStorage` entries; only reader settings and location caches cross.
    @discardableResult
    public static func export(documents: URL, defaults: UserDefaults, webStorage: [String: String], workDirectory: URL, to destination: URL,
                              copyRealm: (URL) throws -> Void, progress: ((LegacyExportProgress) -> Void)? = nil) throws -> URL {
        try? FileManager.default.removeItem(at: workDirectory)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let databaseDirectory = workDirectory.appendingPathComponent("Database")
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true, attributes: attributes)
        let copy = databaseDirectory.appendingPathComponent("legacy.realm")

        progress?(.copyingDatabase)
        try copyRealm(copy)
        progress?(.readingDatabase)
        let contents = try LegacyRealmReader.read(realmAt: copy, workDirectory: workDirectory.appendingPathComponent("Reader"))
        try? FileManager.default.removeItem(at: databaseDirectory)

        var snapshot = contents.snapshot
        snapshot.preferences = LegacyInstallation.capacitorPreferences(defaults)
        snapshot.webStorage = webStorage
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try LegacyArchive.write(snapshot, documents: documents, to: destination) { progress?(.copyingFiles($0)) }
    }
}

public struct LegacyExportResult: Equatable {
    public let url: URL
    public let files: Int
    public let bytes: Int64
}

public final class LegacyExportJob {
    public enum Message {
        public static let insufficientSpace = ""
        public static let databaseUnreadable = ""
        public static let unsupportedVersion = ""
        public static let failed = ""
    }

    public init(documents: URL, exportsDirectory: URL, workDirectory: URL, defaults: UserDefaults, now: @escaping () -> Date = Date.init) {}

    public func run(webStorage: [String: String], copyRealm: (URL) throws -> Void, progress: ((LegacyExportProgress) -> Void)?) throws -> LegacyExportResult {
        throw CocoaError(.featureUnsupported)
    }

    public func discard() throws {}

    public static func message(for error: Error) -> String { "" }
}
