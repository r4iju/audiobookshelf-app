import Combine
import Foundation

/// A book's place in a series. The server stores the sequence as text, such as "2.5" or "10".
public struct SeriesReference: Decodable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let sequence: String?
    public init(id: String, name: String, sequence: String?) { self.id = id; self.name = name; self.sequence = sequence }

    private enum CodingKeys: String, CodingKey { case id, name, sequence }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let text = try? container.decodeIfPresent(String.self, forKey: .sequence) { sequence = text }
        else if let number = try? container.decodeIfPresent(Double.self, forKey: .sequence) { sequence = String(format: "%g", number) }
        else { sequence = nil }
    }
}

/// Expanded items list every series; items filtered by one series carry that series as a single object.
struct SeriesReferences: Decodable {
    let values: [SeriesReference]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([SeriesReference].self) { values = many }
        else if let one = try? container.decode(SeriesReference.self) { values = [one] }
        else { values = [] }
    }
}

extension LibraryItem {
    public var series: [SeriesReference] { media.metadata.series?.values ?? [] }
}

public struct AuthorDetail: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let imagePath: String?
    public var hasImage: Bool { !(imagePath ?? "").isEmpty }
}

public struct SeriesDetail: Decodable, Identifiable {
    public struct Progress: Decodable {
        public let libraryItemIds: [String]
        public let libraryItemIdsFinished: [String]
        public let isFinished: Bool
    }
    public let id: String
    public let name: String
    public let description: String?
    public let progress: Progress?
}

public struct SeriesPage: Decodable {
    public struct Series: Decodable, Identifiable {
        public let id: String
        public let name: String
        public let books: [LibraryItem]?
    }
    public let results: [Series]
    public let total: Int
}

/// The sign-in a page was opened under. Every request carries its revision, so none goes out once another sign-in
/// replaced it, even the same account signing in again, and results are shown only while it is still the current one.
@MainActor final class OpenedSignIn {
    let revision: UUID
    private let api: APIClient
    private var account: AccountIdentity?

    init(api: APIClient) { self.api = api; revision = api.authorizationRevision }

    /// Identifies the account on first use. Throws `CancellationError` once the sign-in changed.
    func confirm() async throws {
        guard api.authorizationRevision == revision else { throw CancellationError() }
        guard account == nil else { return }
        let found = try await api.currentAccount()
        guard api.authorizationRevision == revision else { throw CancellationError() }
        account = found
    }

    var isCurrent: Bool {
        guard api.authorizationRevision == revision, let account, let credentials = api.credentials, let user = credentials.userID else { return false }
        return (try? AccountIdentity(server: credentials.server, userID: user)) == account
    }
}

/// Books of one author or series in the server's order, a page at a time.
@MainActor public final class RelatedBooks: ObservableObject {
    @Published public private(set) var items: [LibraryItem] = []
    @Published public private(set) var total = 0
    @Published public private(set) var loading = false
    @Published public private(set) var error: Error?
    private let signIn: OpenedSignIn
    private let fetch: (_ page: Int, _ authorization: UUID) async throws -> ItemsResponse
    private var nextPage = 0
    private var generation = UUID()

    init(signIn: OpenedSignIn, fetch: @escaping (_ page: Int, _ authorization: UUID) async throws -> ItemsResponse) {
        self.signIn = signIn
        self.fetch = fetch
    }

    public var hasMore: Bool { items.count < total }

    public func reload() async {
        guard signIn.isCurrent else { return }
        generation = UUID()
        items = []; total = 0; nextPage = 0; loading = false; error = nil
        await loadPage()
    }

    /// Loads the next page once a title near the end of those loaded appears.
    public func loadMore(after item: LibraryItem) async {
        guard hasMore, !loading, error == nil, signIn.isCurrent,
              let index = items.firstIndex(of: item), index >= items.count - 12 else { return }
        await loadPage()
    }

    private func loadPage() async {
        let request = generation
        loading = true
        defer { if request == generation { loading = false } }
        do {
            let response = try await fetch(nextPage, signIn.revision)
            guard request == generation, signIn.isCurrent else { return }
            let known = Set(items.map(\.id))
            items += response.results.filter { !known.contains($0.id) }
            total = response.results.isEmpty ? items.count : response.total
            nextPage += 1
        } catch {
            guard request == generation, signIn.isCurrent, !(error is CancellationError) else { return }
            self.error = error
        }
    }
}

/// An author's details, image, series and books within one library. Changes to `books` are published here too.
@MainActor public final class RelatedAuthor: ObservableObject {
    @Published public private(set) var author: AuthorDetail?
    @Published public private(set) var series: [SeriesPage.Series] = []
    @Published public private(set) var imageData: Data?
    @Published public private(set) var error: Error?
    public let books: RelatedBooks
    private let api: APIClient
    private let signIn: OpenedSignIn
    private let id: String
    private let libraryID: String
    private var forwarding: AnyCancellable?

    public init(api: APIClient, id: String, libraryID: String) {
        self.api = api; self.id = id; self.libraryID = libraryID
        let signIn = OpenedSignIn(api: api)
        self.signIn = signIn
        books = RelatedBooks(signIn: signIn) { page, authorization in
            try await api.items(libraryID: libraryID, page: page, filter: APIClient.relatedFilter("authors", id), authorization: authorization)
        }
        forwarding = books.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// The first failure of the details, series or first page of books, or nil once they all loaded.
    public var failure: Error? { error ?? (books.items.isEmpty ? books.error : nil) }

    public func load() async {
        let authorization = signIn.revision
        do { try await signIn.confirm() } catch { return report(error) }
        error = nil
        async let detail = api.author(id: id, authorization: authorization)
        async let found = allSeries(authorization: authorization)
        await books.reload()
        do {
            let loaded = try await detail
            let all = try await found
            guard signIn.isCurrent else { return }
            author = loaded
            series = all
            if loaded.hasImage, imageData == nil,
               let image = try? await api.authorImageData(authorID: id, authorization: authorization), signIn.isCurrent {
                imageData = image
            }
        } catch {
            report(error)
        }
    }

    /// Every page of the author's series, until the server's total is reached or it returns no more.
    private func allSeries(authorization: UUID) async throws -> [SeriesPage.Series] {
        var all: [SeriesPage.Series] = []
        for page in 0... {
            let response = try await api.authorSeries(libraryID: libraryID, authorID: id, page: page, limit: 50, authorization: authorization)
            all += response.results
            if response.results.isEmpty || all.count >= response.total { break }
        }
        return all
    }

    private func report(_ error: Error) {
        guard signIn.isCurrent, !(error is CancellationError) else { return }
        self.error = error
    }
}

/// A series' details and progress within one library, with its books in the server's sequence order.
@MainActor public final class RelatedSeries: ObservableObject {
    @Published public private(set) var series: SeriesDetail?
    @Published public private(set) var error: Error?
    public let books: RelatedBooks
    private let api: APIClient
    private let signIn: OpenedSignIn
    private let id: String
    private let libraryID: String
    private var forwarding: AnyCancellable?

    public init(api: APIClient, id: String, libraryID: String) {
        self.api = api; self.id = id; self.libraryID = libraryID
        let signIn = OpenedSignIn(api: api)
        self.signIn = signIn
        books = RelatedBooks(signIn: signIn) { page, authorization in
            try await api.items(libraryID: libraryID, page: page, filter: APIClient.relatedFilter("series", id), sort: "sequence", authorization: authorization)
        }
        forwarding = books.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public var failure: Error? { error ?? (books.items.isEmpty ? books.error : nil) }

    public func sequence(of item: LibraryItem) -> String? { item.series.first { $0.id == id }?.sequence }

    /// How many books the series has and, when the server reports progress, how many are finished.
    public var summary: String? {
        guard let series else { return nil }
        let count = series.progress?.libraryItemIds.count ?? books.total
        let books = count == 1 ? "1 book" : "\(count) books"
        return series.progress.map { books + " · \($0.libraryItemIdsFinished.count) finished" } ?? books
    }

    public func load() async {
        let authorization = signIn.revision
        do { try await signIn.confirm() } catch { return report(error) }
        error = nil
        async let detail = api.series(libraryID: libraryID, id: id, authorization: authorization)
        await books.reload()
        do {
            let loaded = try await detail
            if signIn.isCurrent { series = loaded }
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard signIn.isCurrent, !(error is CancellationError) else { return }
        self.error = error
    }
}
