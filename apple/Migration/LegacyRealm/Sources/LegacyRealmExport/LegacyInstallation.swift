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

/// Runs inside the legacy app: writes a credential-free archive the user carries to a separately
/// identified app (such as the native preview) through the Files app.
public enum LegacyArchiveExporter {
    /// - Parameter realmCopy: a consistent copy of the open legacy Realm, made by the legacy app
    ///   with `Realm.writeCopy(toFile:)`; it is read, never modified.
    @discardableResult
    public static func export(documents: URL, realmCopy: URL, defaults: UserDefaults, webStorage: [String: String], workDirectory: URL, to destination: URL) throws -> URL {
        let contents = try LegacyRealmReader.read(realmAt: realmCopy, workDirectory: workDirectory)
        var snapshot = contents.snapshot
        snapshot.preferences = LegacyInstallation.capacitorPreferences(defaults)
        snapshot.webStorage = webStorage
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try LegacyArchive.write(snapshot, documents: documents, to: destination)
    }
}
