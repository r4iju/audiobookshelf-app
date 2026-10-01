import SwiftUI

struct SearchResult: Identifiable, Hashable {
    let item: LibraryItem
    let episodeID: String?
    var id: String { item.id + "#" + (episodeID ?? "") }
    var route: Route { episodeID.map { .episode(item, episodeID: $0) } ?? .item(item) }
}

struct HomeShelf: Identifiable {
    let id: String
    let shelfID: String
    let title: String
    let items: [LibraryItem]
}

/// Account, libraries, home shelves, listening progress and artwork shared by every TV tab.
@MainActor final class CatalogStore: ObservableObject {
    let api: APIClient
    @Published private(set) var signedIn: Bool
    @Published var needsSignIn = false
    @Published private(set) var signingIn = false
    @Published private(set) var signInError: String?
    @Published private(set) var libraries: [Library] = []
    @Published private(set) var shelves: [HomeShelf] = []
    @Published private(set) var loadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var progress: [String: MediaProgress] = [:]
    /// Changes whenever a title moves between not started, in progress and finished, which server progress filters depend on.
    @Published private(set) var progressRevision = 0
    private var generation = UUID()
    private var account = UUID()
    /// Changes on sign-out, so work started for one account can tell it no longer applies.
    var accountID: UUID { account }
    private var covers: [String: UIImage] = [:]
    private var missingCovers: Set<String> = []

    static let lastServerKey = "lastServer", lastUsernameKey = "lastUsername"

    init(api: APIClient) {
        self.api = api
        signedIn = api.credentials != nil
    }

    var serverAddress: String { api.credentials?.server ?? "" }
    var username: String { api.credentials?.username ?? "" }

    func login(server: String, username: String, password: String) async {
        signingIn = true
        signInError = nil
        defer { signingIn = false }
        do {
            try await api.login(server: server, username: username, password: password)
            UserDefaults.standard.set(server, forKey: Self.lastServerKey)
            UserDefaults.standard.set(username, forKey: Self.lastUsernameKey)
            needsSignIn = false
            signedIn = true
        } catch { signInError = Self.recovery(for: error) }
    }

    func loadCatalog() async {
        generation = UUID()
        let request = generation
        loadingCatalog = true
        catalogError = nil
        defer { if request == generation { loadingCatalog = false } }
        do {
            let found = try await api.libraries()
            guard request == generation else { return }
            libraries = found
            async let user = api.me()
            let loaded = try await Self.eachLibrary(found) { library in
                try await self.api.personalized(libraryID: library.id).filter { !$0.entities.isEmpty }.map {
                    HomeShelf(id: library.id + "." + $0.id, shelfID: $0.id, title: Self.shelfTitle($0.id, library: library, among: found), items: $0.entities)
                }
            }
            let current = try await user
            guard request == generation else { return }
            shelves = loaded
            remember(current)
        } catch {
            guard request == generation else { return }
            fail(error)
        }
    }

    func refreshProgress() async {
        guard let user = try? await api.me() else { return }
        remember(user)
    }

    func remember(_ user: CurrentUser) {
        let updated = Dictionary(user.mediaProgress.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        if updated.mapValues(Self.stage) != progress.mapValues(Self.stage) { progressRevision += 1 }
        progress = updated
    }

    private static func stage(_ progress: MediaProgress) -> Int {
        progress.isFinished == true ? 2 : (progress.currentTime ?? 0) > 0 ? 1 : 0
    }

    func progress(itemID: String, episodeID: String? = nil) -> MediaProgress? {
        progress[itemID + ":" + (episodeID ?? "book")]
    }

    func search(_ text: String) async throws -> [SearchResult] {
        let responses = try await Self.eachLibrary(libraries) { library in
            [try await self.api.search(libraryID: library.id, query: text, limit: 25)]
        }
        return Self.merge(responses)
    }

    /// A podcast and each of its matching episodes are separate results; only exact repeats across libraries are dropped.
    nonisolated static func merge(_ responses: [SearchResponse]) -> [SearchResult] {
        let results = responses.flatMap { response in
            response.items.map { SearchResult(item: $0, episodeID: nil) }
                + (response.episodes ?? []).map { SearchResult(item: $0.libraryItem, episodeID: $0.libraryItem.recentEpisode?.id) }
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    /// Server and network trouble is temporary; only a server saying there is no cover is worth remembering.
    nonisolated static func coverIsAbsent(after error: Error) -> Bool {
        error as? APIError == .http(404)
    }

    /// One unavailable library must not hide the others; fail only when every library fails.
    private static func eachLibrary<T>(_ libraries: [Library], _ load: (Library) async throws -> [T]) async throws -> [T] {
        var results: [T] = []
        var failure: Error?
        for library in libraries {
            do { results += try await load(library) }
            catch { failure = failure ?? error }
        }
        if let failure, results.isEmpty { throw failure }
        return results
    }

    func cover(itemID: String) async -> UIImage? {
        if let cached = covers[itemID] { return cached }
        if missingCovers.contains(itemID) { return nil }
        let request = account
        let data: Data
        do { data = try await api.coverData(itemID: itemID) }
        catch {
            if request == account, Self.coverIsAbsent(after: error) { missingCovers.insert(itemID) }
            return nil
        }
        guard request == account else { return nil }
        guard let image = UIImage(data: data) else { missingCovers.insert(itemID); return nil }
        if covers.count >= 240 { covers.removeAll() }
        covers[itemID] = image
        return image
    }

    func signOut() throws {
        try api.signOut()
        generation = UUID(); account = UUID()
        libraries = []; shelves = []; progress = [:]; covers = [:]; missingCovers = []
        catalogError = nil
        loadingCatalog = false
        signedIn = false
        needsSignIn = false
    }

    private func fail(_ failure: Error) {
        if failure is CancellationError { return }
        noteAuthentication(failure)
        catalogError = Self.recovery(for: failure)
    }

    func noteAuthentication(_ failure: Error) {
        if failure as? APIError == .signInRequired { needsSignIn = true }
    }

    /// Explains connection failures in terms of what the person can change on the TV or server.
    static func recovery(for failure: Error) -> String {
        if let failure = failure as? URLError {
            switch failure.code {
            case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .secureConnectionFailed:
                return "This Apple TV does not trust the server’s HTTPS certificate. Install and trust your certificate authority profile on the TV, or use the server’s local HTTP address."
            case .cannotFindHost, .dnsLookupFailed:
                return "The server address could not be found. Check the host name and that the TV is on the same network."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                return "The server could not be reached. Check that it is running and that the TV is on the network, then try again."
            default: break
            }
        }
        if failure as? APIError == .http(404) { return "No Audiobookshelf server answered at this address. Include any reverse-proxy path, such as https://example.com/audiobookshelf." }
        return failure.localizedDescription
    }

    private static func shelfTitle(_ id: String, library: Library, among libraries: [Library]) -> String {
        let known = ["continue-listening": "Continue Listening", "continue-series": "Continue Series", "recently-added": "Recently Added",
                     "listen-again": "Listen Again", "discover": "Discover", "newest-episodes": "Newest Episodes", "episodes-recently-added": "Newest Episodes"]
        let title = known[id] ?? id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return libraries.count > 1 ? "\(title) · \(library.name)" : title
    }
}
