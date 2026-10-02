import Foundation
import Security

/// Read-only access to the legacy refresh tokens. Succeeds only when the running app shares the
/// legacy app's Keychain access group (same team and bundle identifier); the native preview's
/// distinct identity cannot see these items. Never deletes or rewrites them, so the legacy items
/// remain for rollback.
public struct LegacyKeychainRefreshTokens: LegacyRefreshTokenReading {
    public static let service = "AudiobookshelfRefreshTokens"

    public init() {}

    public func refreshToken(forConnectionID id: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "refresh_token_\(id)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
