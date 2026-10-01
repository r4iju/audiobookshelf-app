import Foundation

@MainActor public final class APIClient {
    public private(set) var credentials: Credentials?
    private let store: CredentialStore
    private let session: URLSession
    private var refreshTask: Task<Void, Error>?
    private var authGeneration = UUID()

    public init(store: CredentialStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
        credentials = try? store.load()
    }

    public func login(server: String, username: String, password: String) async throws {
        let address = try ServerAddress(server)
        var request = URLRequest(url: try address.url(path: "login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-return-tokens")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let data = try await send(request)
        try completeBrowserLogin(server: address.base.absoluteString, response: data)
    }

    public func completeBrowserLogin(server: String, response data: Data) throws {
        let address = try ServerAddress(server)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let token = response.user.bearerToken, !token.isEmpty else { throw APIError.signInRequired }
        let value = Credentials(server: address.base.absoluteString, accessToken: token, refreshToken: response.user.refreshToken, userID: response.user.id, username: response.user.username)
        try store.save(value)
        refreshTask?.cancel()
        refreshTask = nil
        authGeneration = UUID()
        credentials = value
    }

    public func signOut() throws {
        refreshTask?.cancel()
        refreshTask = nil
        try store.clear()
        authGeneration = UUID()
        credentials = nil
    }

    public func restoreSavedCredentials() throws {
        let restored = try store.load()
        refreshTask?.cancel()
        refreshTask = nil
        authGeneration = UUID()
        credentials = restored
    }

    public func me() async throws -> CurrentUser { try await get("api/me") }

    public func saveBookmark(itemID: String, time: Double, title: String, editing: Bool) async throws {
        _ = try await request("api/me/item/\(itemID)/bookmark", method: editing ? "PATCH" : "POST", body: ["time": time, "title": title])
    }

    public func deleteBookmark(itemID: String, time: Double) async throws {
        _ = try await request("api/me/item/\(itemID)/bookmark/\(time)", method: "DELETE")
    }

    public func currentAccount() async throws -> AccountIdentity {
        guard let original = credentials else { throw APIError.signInRequired }
        if let id = original.userID { return try AccountIdentity(server: original.server, userID: id) }
        let generation = authGeneration
        let user = try await me()
        guard generation == authGeneration, let current = credentials else { throw CancellationError() }
        let identified = Credentials(server: current.server, accessToken: current.accessToken, refreshToken: current.refreshToken, userID: user.id, username: user.username)
        try store.replace(identified, replacing: current)
        credentials = identified
        return try AccountIdentity(server: identified.server, userID: user.id)
    }

    public func syncListening(_ record: ListeningRecord) async throws {
        guard try await currentAccount() == record.account else { throw APIError.signInRequired }
        let response = try await request("api/session/local-all", method: "POST", body: [
            "sessions": [record.payload], "deviceInfo": Self.deviceInfo(id: record.deviceID)
        ])
        struct Result: Decodable { let id: String; let success: Bool }
        struct Response: Decodable { let results: [Result] }
        let acknowledged = try JSONDecoder().decode(Response.self, from: response)
        guard acknowledged.results.contains(where: { $0.id == record.id && $0.success }) else { throw APIError.http(500) }
    }

    public func personalized(libraryID: String) async throws -> [PersonalizedShelf] {
        try await get("api/libraries/\(libraryID)/personalized", query: [URLQueryItem(name: "minified", value: "1")])
    }

    public func libraries() async throws -> [Library] {
        let response: LibrariesResponse = try await get("api/libraries")
        return response.libraries
    }
    public func items(libraryID: String, page: Int, filter: String? = nil, sort: String = "media.metadata.title", descending: Bool = false) async throws -> ItemsResponse {
        try await get("api/libraries/\(libraryID)/items", query: [
            URLQueryItem(name: "limit", value: "60"), URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "desc", value: descending ? "1" : "0"), URLQueryItem(name: "minified", value: "1")
        ] + (filter.map { [URLQueryItem(name: "filter", value: $0)] } ?? []))
    }
    public func search(libraryID: String, query: String, limit: Int) async throws -> SearchResponse {
        try await get("api/libraries/\(libraryID)/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))])
    }
    public func filters(libraryID: String) async throws -> LibraryFilters { try await get("api/libraries/\(libraryID)/filterdata") }
    public func item(id: String) async throws -> LibraryItem { try await get("api/items/\(id)", query: [URLQueryItem(name: "expanded", value: "1")]) }

    public func play(itemID: String, episodeID: String? = nil, deviceID: String) async throws -> PlaybackSession {
        var path = "api/items/\(itemID)/play"
        if let episodeID { path += "/\(episodeID)" }
        let data = try await request(path, method: "POST", body: [
            "forceDirectPlay": true, "mediaPlayer": "AVPlayer",
            "deviceInfo": Self.deviceInfo(id: deviceID)
        ])
        let result = try JSONDecoder().decode(PlaybackSession.self, from: data)
        guard !result.audioTracks.isEmpty else { throw APIError.noAudio }
        return result
    }
    public func report(sessionID: String, report: ProgressReport, close: Bool = false) async throws {
        let body = try JSONEncoder().encode(report)
        _ = try await request("api/session/\(sessionID)/\(close ? "close" : "sync")", method: "POST", bodyData: body)
    }

    public func closeStream(sessionID: String) async throws {
        do { _ = try await request("api/session/\(sessionID)/close", method: "POST", body: [:]) }
        catch APIError.http(404) { return }
    }

    public func releaseStream(sessionID: String) throws {
        guard let credentials else { throw APIError.signInRequired }
        var request = URLRequest(url: try ServerAddress(credentials.server).url(path: "api/session/\(sessionID)/close"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        // Account switching must work offline. This cleanup uses the original server/token;
        // durable listening remains in the account's journal until separately acknowledged.
        Task { [session] in _ = try? await session.data(for: request) }
    }

    private static func deviceInfo(id: String) -> [String: String] {
        #if os(iOS)
        return ["deviceId": id, "clientName": "Audiobookshelf Native", "manufacturer": "Apple", "model": "iPhone / iPad"]
        #else
        return ["deviceId": id, "clientName": "Audiobookshelf TV", "manufacturer": "Apple", "model": "Apple TV"]
        #endif
    }

    public func mediaURL(_ path: String) throws -> URL {
        guard let credentials else { throw APIError.signInRequired }
        return try ServerAddress(credentials.server).mediaURL(path)
    }

    public func coverData(itemID: String) async throws -> Data {
        try await request("api/items/\(itemID)/cover", query: [URLQueryItem(name: "width", value: "500")])
    }

    public func validToken() async throws -> String {
        if let refreshTask { try await refreshTask.value }
        if let value = credentials, value.refreshToken != nil, Self.expiresSoon(value.accessToken) {
            try await refresh()
        }
        guard let credentials else { throw APIError.signInRequired }
        return credentials.accessToken
    }

    private static func expiresSoon(_ token: String) -> Bool {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return false }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = claims["exp"] as? Double else { return false }
        return expiry < Date().timeIntervalSince1970 + 60
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, query: query))
    }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil, bodyData: Data? = nil, retry: Bool = true) async throws -> Data {
        guard let credentials else { throw APIError.signInRequired }
        let generation = authGeneration
        var request = URLRequest(url: try ServerAddress(credentials.server).url(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        else { request.httpBody = bodyData }
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let data = try await send(request)
            guard authGeneration == generation else { throw CancellationError() }
            return data
        }
        catch APIError.http(401) {
            guard authGeneration == generation else { throw CancellationError() }
            guard retry, credentials.refreshToken != nil else { throw APIError.signInRequired }
            // Concurrent cover and library requests share one refresh; a completed refresh also satisfies an older 401.
            if self.credentials?.accessToken == credentials.accessToken { try await refresh() }
            return try await self.request(path, method: method, query: query, body: body, bodyData: bodyData, retry: false)
        }
    }

    private func refresh() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard let original = credentials, let token = original.refreshToken else { throw APIError.signInRequired }
        let generation = authGeneration
        let task = Task { @MainActor in
            var request = URLRequest(url: try ServerAddress(original.server).url(path: "auth/refresh"))
            request.httpMethod = "POST"
            request.setValue(token, forHTTPHeaderField: "x-refresh-token")
            let response = try JSONDecoder().decode(AuthResponse.self, from: await send(request))
            try Task.checkCancellation()
            guard let bearer = response.user.bearerToken, !bearer.isEmpty,
                  authGeneration == generation else { throw APIError.signInRequired }
            guard original.userID == nil || response.user.id == nil || original.userID == response.user.id else { throw APIError.signInRequired }
            let updated = Credentials(server: original.server, accessToken: bearer, refreshToken: response.user.refreshToken ?? token, userID: original.userID ?? response.user.id, username: response.user.username ?? original.username)
            try store.replace(updated, replacing: original)
            credentials = updated
        }
        refreshTask = task
        defer { if authGeneration == generation { refreshTask = nil } }
        do { try await task.value }
        catch APIError.http(401) { throw APIError.signInRequired }
        catch APIError.http(403) { throw APIError.signInRequired }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.http(0) }
        guard (200...299).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        return data
    }
}
