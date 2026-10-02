import Foundation
import Security

@MainActor final class KeychainCredentials: CredentialStore {
    struct Connection: Codable, Identifiable {
        let id: String
        var credentials: Credentials
        var libraryID: String?
    }
    struct Summary: Identifiable {
        let id: String
        let server: String
        let username: String
    }
    private struct Document: Codable {
        let version: Int
        var connections: [Connection]
        var activeID: String?
    }
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.forkzed.audiobookshelf.native.preview",
        kSecAttrAccount as String: "server"
    ]

    func load() throws -> Credentials? {
        let saved = try document()
        return saved.connections.first { $0.id == saved.activeID }?.credentials
    }

    func summaries() throws -> [Summary] {
        try document().connections.map { Summary(id: $0.id, server: $0.credentials.server, username: $0.credentials.username ?? "Saved account") }
    }

    func activeConnection() throws -> Connection? {
        let saved = try document()
        return saved.connections.first { $0.id == saved.activeID }
    }

    func select(id: String) throws {
        var saved = try document()
        guard saved.connections.contains(where: { $0.id == id }) else { throw APIError.signInRequired }
        saved.activeID = id
        try write(saved)
    }

    func selectLibrary(_ id: String?) throws {
        var saved = try document()
        guard let index = saved.connections.firstIndex(where: { $0.id == saved.activeID }) else { throw APIError.signInRequired }
        saved.connections[index].libraryID = id
        try write(saved)
    }

    private func document() throws -> Document {
        guard let data = try read() else { return Document(version: 1, connections: [], activeID: nil) }
        if let saved = try? JSONDecoder().decode(Document.self, from: data) {
            guard saved.version == 1 else { throw KeychainError(status: errSecDecode) }
            return saved
        }
        let legacy = try JSONDecoder().decode(Credentials.self, from: data)
        let id = "migrated-preview-connection"
        return Document(version: 1, connections: [Connection(id: id, credentials: legacy)], activeID: id)
    }

    private func read() throws -> Data? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }

    func save(_ credentials: Credentials) throws {
        var saved = try document()
        let server = try ServerAddress(credentials.server).base
        let identity = try credentials.userID.map { try AccountIdentity(server: credentials.server, userID: $0) }
        let index = try saved.connections.firstIndex { existing in
            if let id = existing.credentials.userID, let identity {
                return try AccountIdentity(server: existing.credentials.server, userID: id) == identity
            }
            guard existing.id == saved.activeID, existing.credentials.userID == nil,
                  existing.credentials.accessToken == credentials.accessToken else { return false }
            return try ServerAddress(existing.credentials.server).base == server
        }
        if let index {
            saved.connections[index].credentials = credentials
            saved.activeID = saved.connections[index].id
        } else {
            let connection = Connection(id: UUID().uuidString, credentials: credentials)
            saved.connections.append(connection)
            saved.activeID = connection.id
        }
        try write(saved)
    }

    private func write(_ saved: Document) throws {
        let data = try JSONEncoder().encode(saved)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(insertion as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainError(status: result) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    func replace(_ credentials: Credentials, replacing original: Credentials) throws {
        var saved = try document()
        guard let index = saved.connections.firstIndex(where: { $0.id == saved.activeID }),
              saved.connections[index].credentials.accessToken == original.accessToken,
              try ServerAddress(saved.connections[index].credentials.server).base == ServerAddress(original.server).base,
              try ServerAddress(credentials.server).base == ServerAddress(original.server).base,
              original.userID == nil || credentials.userID == original.userID else { throw APIError.signInRequired }
        saved.connections[index].credentials = credentials
        try write(saved)
    }

    func clear() throws {
        var saved = try document()
        saved.connections.removeAll { $0.id == saved.activeID }
        saved.activeID = nil
        try write(saved)
    }

    func resetPreviewAccounts() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    #if DEBUG && targetEnvironment(simulator)
    func seedLegacyPreviewAccount() throws {
        try resetPreviewAccounts()
        let credentials = Credentials(server: "http://127.0.0.1:19765/abs", accessToken: "expired", refreshToken: "refresh")
        var insertion = query
        insertion[kSecValueData as String] = try JSONEncoder().encode(credentials)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
    #endif

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { NativeStrings.current("Unable to save the server login in Keychain ({0}).", status) }
    }
}
