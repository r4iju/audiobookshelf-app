import Foundation

@MainActor public final class APIClient {
    public private(set) var credentials: Credentials?
    private let store: CredentialStore
    private let session: URLSession
    private var refreshTask: Task<Void, Error>?
    private var authGeneration = UUID()
    /// Changes on every sign-in, sign-out and credential restore (never on token refresh). Compare it before and
    /// after a sequence of requests to know they all ran for the same signed-in account.
    public var authorizationRevision: UUID { authGeneration }
    public var progressResetCommitted: ((AccountIdentity, LibraryItem, String?) throws -> Void)?

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

    public func listeningStats() async throws -> ListeningStats { try await get("api/me/listening-stats") }

    public func yearListeningStats(_ year: Int) async throws -> YearListeningStats {
        guard (2000...9999).contains(year) else { throw APIError.http(400) }
        return try await get("api/me/stats/year/\(year)")
    }

    public func serverYearStats(_ year: Int) async throws -> ServerYearStats {
        guard (2000...9999).contains(year) else { throw APIError.http(400) }
        return try await get("api/stats/year/\(year)")
    }

    public func me() async throws -> CurrentUser { try await get("api/me") }

    /// `issuing` as in `syncListening`.
    public func setFinished(itemID: String, episodeID: String?, finished: Bool, progressGeneration: Int? = nil, issuing: IssuingHook? = nil) async throws {
        let path = "api/me/progress/\(itemID)" + (episodeID.map { "/" + $0 } ?? "")
        var body: [String: Any] = ["isFinished": finished]
        if let progressGeneration { body["progressGeneration"] = progressGeneration }
        _ = try await request(path, method: "PATCH", body: body, issuing: issuing)
    }

    public func audioGroups(libraryID: String, kind: AudioGroupKind) async throws -> AudioGroupPage {
        try await get("api/libraries/\(libraryID)/\(kind.rawValue)")
    }
    public func audioGroup(id: String, kind: AudioGroupKind) async throws -> AudioGroup {
        try await get("api/\(kind.rawValue)/\(id)")
    }
    public func saveAudioGroup(id: String?, libraryID: String, kind: AudioGroupKind, name: String, description: String, members: [AudioGroupMember], account: AccountIdentity) async throws -> AudioGroup {
        guard try await currentAccount() == account else { throw APIError.signInRequired }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(members.map(\.id)).count == members.count,
              !(members.isEmpty && (id == nil || kind == .playlist)) else { throw APIError.http(400) }
        let key = kind == .collection ? "books" : "items"
        func payload(_ members: [AudioGroupMember]) -> Any {
            if kind == .collection { return members.map(\.libraryItemId) }
            return members.map { member -> [String: String] in
                var value = ["libraryItemId": member.libraryItemId]
                if let episodeID = member.episodeId { value["episodeId"] = episodeID }
                return value
            }
        }
        if let id {
            let original = try await audioGroup(id: id, kind: kind)
            guard original.libraryId == libraryID, try await currentAccount() == account else { throw APIError.signInRequired }
            let desired = Set(members.map(\.id)), existing = Set(original.members.map(\.id))
            let added = members.filter { !existing.contains($0.id) }
            let removed = original.members.filter { !desired.contains($0.id) }
            var saved = false
            do {
                if !added.isEmpty {
                    _ = try await request("api/\(kind.rawValue)/\(id)/batch/add", method: "POST", body: [key: payload(added)])
                    saved = true
                }
                guard try await currentAccount() == account else { throw APIError.signInRequired }
                if !removed.isEmpty {
                    _ = try await request("api/\(kind.rawValue)/\(id)/batch/remove", method: "POST", body: [key: payload(removed)])
                    saved = true
                }
                guard try await currentAccount() == account else { throw APIError.signInRequired }
                let data = try await request("api/\(kind.rawValue)/\(id)", method: "PATCH", body: ["name": name, "description": description, key: payload(members)])
                guard try await currentAccount() == account else { throw AudioGroupPartialSave(underlying: APIError.signInRequired) }
                return try JSONDecoder().decode(AudioGroup.self, from: data)
            } catch let error where saved && !(error is AudioGroupPartialSave) {
                throw AudioGroupPartialSave(underlying: error)
            }
        }
        let data = try await request("api/\(kind.rawValue)", method: "POST", body: ["libraryId": libraryID, "name": name, "description": description, key: payload(members)])
        guard try await currentAccount() == account else { throw APIError.signInRequired }
        return try JSONDecoder().decode(AudioGroup.self, from: data)
    }
    public func deleteAudioGroup(id: String, kind: AudioGroupKind, account: AccountIdentity) async throws {
        guard try await currentAccount() == account else { throw APIError.signInRequired }
        _ = try await request("api/\(kind.rawValue)/\(id)", method: "DELETE")
        guard try await currentAccount() == account else { throw APIError.signInRequired }
    }

    public func podcastFeed(url: String) async throws -> PodcastFeed {
        let data = try await request("api/podcasts/feed", method: "POST", body: ["rssFeed": url])
        return try JSONDecoder().decode(PodcastFeedResponse.self, from: data).podcast
    }
    public func discoverPodcasts(term: String) async throws -> [PodcastDiscovery] {
        try await get("api/search/podcast", query: [URLQueryItem(name: "term", value: term)])
    }

    public func downloadFeedEpisodes(itemID: String, episodes: [PodcastFeedEpisode]) async throws {
        let data = try JSONEncoder().encode(episodes)
        guard data.count < 5 * 1024 * 1024 else { throw APIError.podcastRequestTooLarge }
        _ = try await request("api/podcasts/\(itemID)/download-episodes", method: "POST", bodyData: data)
    }
    public func podcastDownloads(itemID: String) async throws -> [PodcastDownload] {
        let response: PodcastDownloads = try await get("api/podcasts/\(itemID)/downloads")
        return response.downloads
    }

    public func createPodcast(libraryID: String, folder: LibraryFolder, title: String, author: String, description: String, feed: PodcastFeed, feedURL: String, autoDownload: Bool, discovery: PodcastDiscovery? = nil) async throws -> LibraryItem {
        let filename = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, filename != ".", filename != ".." else { throw APIError.invalidPodcastTitle }
        let path = (folder.fullPath as NSString).appendingPathComponent(filename)
        let itunesID = discovery.map { String($0.id) } ?? ""
        let artistID = discovery?.artistId.map(String.init) ?? ""
        let metadata: [String: Any] = [
            "title": title, "author": author, "description": description,
            "feedUrl": discovery?.feedUrl ?? feed.metadata.feedUrl ?? feedURL,
            "imageUrl": discovery?.cover ?? feed.metadata.image ?? "",
            "genres": discovery?.genres ?? feed.metadata.categories ?? [],
            "releaseDate": discovery?.releaseDate ?? "",
            "itunesId": itunesID, "itunesArtistId": artistID, "itunesPageUrl": discovery?.pageUrl ?? ""
        ]
        let media: [String: Any] = ["metadata": metadata, "autoDownloadEpisodes": autoDownload]
        let body: [String: Any] = ["libraryId": libraryID, "folderId": folder.id, "path": path, "media": media]
        let data = try await request("api/podcasts", method: "POST", body: body)
        return try JSONDecoder().decode(LibraryItem.self, from: data)
    }

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

    /// `issuing` runs right before each transmission of the request, the first and any resent
    /// after a 401, and nothing is sent when it throws; see `IssuingHook`.
    public func syncListening(_ record: ListeningRecord, issuing: IssuingHook? = nil) async throws {
        guard try await currentAccount() == record.account else { throw APIError.signInRequired }
        let response = try await request("api/session/local-all", method: "POST", body: [
            "sessions": [record.payload], "deviceInfo": Self.deviceInfo(id: record.deviceID)
        ], issuing: issuing)
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
    /// With `authorization`, only for that sign-in, like `coverData(itemID:authorization:)`.
    public func items(libraryID: String, page: Int, filter: String? = nil, sort: String = "media.metadata.title", descending: Bool = false, authorization: UUID? = nil) async throws -> ItemsResponse {
        try await get("api/libraries/\(libraryID)/items", pinned: authorization, query: [
            URLQueryItem(name: "limit", value: "60"), URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "desc", value: descending ? "1" : "0"), URLQueryItem(name: "minified", value: "1")
        ] + (filter.map { [URLQueryItem(name: "filter", value: $0)] } ?? []))
    }
    public func search(libraryID: String, query: String, limit: Int) async throws -> SearchResponse {
        try await get("api/libraries/\(libraryID)/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))])
    }
    /// A library filter such as `authors.<base64 id>` or `series.<base64 id>`, as the server's filter decoder expects.
    public static func relatedFilter(_ group: String, _ value: String) -> String { group + "." + Data(value.utf8).base64EncodedString() }
    public func author(id: String, authorization: UUID? = nil) async throws -> AuthorDetail { try await get("api/authors/\(id)", pinned: authorization) }
    /// A series with progress over its books in `libraryID`. The server's global `api/series/:id` is deprecated
    /// because a series is not specific to one library.
    public func series(libraryID: String, id: String, authorization: UUID? = nil) async throws -> SeriesDetail {
        try await get("api/libraries/\(libraryID)/series/\(id)", pinned: authorization, query: [URLQueryItem(name: "include", value: "progress")])
    }
    /// The series in a library that contain at least one book by the author, sorted by name.
    public func authorSeries(libraryID: String, authorID: String, page: Int, limit: Int = 20, authorization: UUID? = nil) async throws -> SeriesPage {
        try await get("api/libraries/\(libraryID)/series", pinned: authorization, query: [
            URLQueryItem(name: "filter", value: Self.relatedFilter("authors", authorID)), URLQueryItem(name: "sort", value: "name"),
            URLQueryItem(name: "desc", value: "0"), URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "minified", value: "1")
        ])
    }
    /// Only for the sign-in identified by `authorization`, like `coverData(itemID:authorization:)`.
    public func authorImageData(authorID: String, authorization: UUID) async throws -> Data {
        try await request("api/authors/\(authorID)/image", query: [URLQueryItem(name: "width", value: "400")], pinned: authorization)
    }
    /// The signed-in user and the e-reader devices the server lets them use, from the same payload as sign-in.
    public func sessionAuthorization(authorization: UUID) async throws -> SessionAuthorization {
        try JSONDecoder().decode(SessionAuthorization.self, from: await request("api/authorize", method: "POST", pinned: authorization))
    }
    /// The expanded item with its open RSS feed, if any.
    public func itemActions(id: String, authorization: UUID) async throws -> ItemActionsDetail {
        try await get("api/items/\(id)", pinned: authorization, query: [URLQueryItem(name: "expanded", value: "1"), URLQueryItem(name: "include", value: "rssfeed")])
    }
    public func openFeed(itemID: String, serverAddress: String, slug: String, preventIndexing: Bool, ownerName: String, ownerEmail: String, authorization: UUID) async throws -> RSSFeed {
        struct Opened: Decodable { let feed: RSSFeed }
        let data = try await request("api/feeds/item/\(itemID)/open", method: "POST", body: [
            "serverAddress": serverAddress, "slug": slug,
            "metadataDetails": ["preventIndexing": preventIndexing, "ownerName": ownerName, "ownerEmail": ownerEmail]
        ], pinned: authorization)
        return try JSONDecoder().decode(Opened.self, from: data).feed
    }
    public func closeFeed(id: String, authorization: UUID) async throws {
        _ = try await request("api/feeds/\(id)/close", method: "POST", pinned: authorization)
    }
    public func sendEbookToDevice(itemID: String, deviceName: String, authorization: UUID) async throws {
        _ = try await request("api/emails/send-ebook-to-device", method: "POST", body: ["libraryItemId": itemID, "deviceName": deviceName], pinned: authorization)
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

    public func ebookData(itemID: String, ebook: EbookFile) async throws -> Data {
        guard !ebook.ino.isEmpty, !ebook.ino.contains("/"), !ebook.ino.contains("..") else { throw APIError.unsafeMediaURL }
        return try await request("api/items/\(itemID)/file/\(ebook.ino)")
    }
    /// The ID of the signed-in user's progress row for the media, or nil when there is none, only
    /// for the sign-in identified by `authorization`. Server 2.30 deletes progress by this ID.
    public func progressRowID(itemID: String, episodeID: String?, authorization: UUID) async throws -> String? {
        struct Row: Decodable { let id: String }
        do { return try JSONDecoder().decode(Row.self, from: await request("api/me/progress/\(itemID)" + (episodeID.map { "/\($0)" } ?? ""), pinned: authorization)).id }
        catch APIError.http(404) { return nil }
    }

    /// Deletes a progress row, only for the sign-in identified by `authorization`. Server 2.30
    /// answers success for a row that is already gone.
    public func resetMissingProgress(itemID: String, episodeID: String?, resetID: String, authorization: UUID) async throws {
        _ = try await request("api/me/progress/\(itemID)" + (episodeID.map { "/\($0)" } ?? "") + "/reset", method: "POST", body: ["resetId": resetID], pinned: authorization)
    }

    public func deleteProgress(rowID: String, authorization: UUID) async throws {
        _ = try await request("api/me/progress/\(rowID)", method: "DELETE", pinned: authorization)
    }

    /// `issuing` as in `syncListening`.
    public func saveReading(account: AccountIdentity, itemID: String, location: String, progress: Double, updatedAt: Double? = nil, progressGeneration: Int? = nil, issuing: IssuingHook? = nil) async throws {
        guard try await currentAccount() == account else { throw APIError.signInRequired }
        var body: [String: Any] = ["ebookLocation": location, "ebookProgress": progress]
        if let updatedAt { body["updatedAt"] = updatedAt }
        if let progressGeneration { body["progressGeneration"] = progressGeneration }
        _ = try await request("api/me/progress/\(itemID)", method: "PATCH", body: body, issuing: issuing)
    }

    public func coverData(itemID: String) async throws -> Data {
        try await request("api/items/\(itemID)/cover", query: [URLQueryItem(name: "width", value: "500")])
    }

    /// Like `coverData(itemID:)`, but only for the sign-in identified by `authorization` (an earlier
    /// `authorizationRevision`). Throws `CancellationError` without sending, or before returning data, once it changed,
    /// including after a 401 refresh retry.
    public func coverData(itemID: String, authorization: UUID) async throws -> Data {
        try await request("api/items/\(itemID)/cover", query: [URLQueryItem(name: "width", value: "500")], pinned: authorization)
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

    private func get<T: Decodable>(_ path: String, pinned: UUID? = nil, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, query: query, pinned: pinned))
    }

    /// Runs right before one transmission and returns what receives its outcome: nil once the
    /// server answered with success, otherwise the error, `APIError.http` for any other answer.
    public typealias IssuingHook = @MainActor (URLRequest) throws -> @MainActor (Error?) -> Void

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil, bodyData: Data? = nil, retry: Bool = true, pinned: UUID? = nil, issuing: IssuingHook? = nil) async throws -> Data {
        if let pinned, pinned != authGeneration { throw CancellationError() }
        guard let credentials else { throw APIError.signInRequired }
        let generation = authGeneration
        var request = URLRequest(url: try ServerAddress(credentials.server).url(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        else { request.httpBody = bodyData }
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let transmitted = try issuing?(request)
        do {
            let data = try await send(request, transmitted: transmitted)
            guard authGeneration == generation else { throw CancellationError() }
            return data
        }
        catch APIError.http(401) {
            guard authGeneration == generation else { throw CancellationError() }
            guard retry, credentials.refreshToken != nil else { throw APIError.signInRequired }
            // Concurrent cover and library requests share one refresh; a completed refresh also satisfies an older 401.
            if self.credentials?.accessToken == credentials.accessToken { try await refresh() }
            return try await self.request(path, method: method, query: query, body: body, bodyData: bodyData, retry: false, pinned: pinned, issuing: issuing)
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

    private func send(_ request: URLRequest, transmitted: (@MainActor (Error?) -> Void)? = nil) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.http(0) }
            guard (200...299).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
            transmitted?(nil)
            return data
        } catch {
            transmitted?(error)
            throw error
        }
    }
}
