import Foundation

struct LibrarySort: Hashable, Identifiable {
    let field: String
    let descending: Bool
    let title: String
    var id: String { field + (descending ? ".descending" : ".ascending") }

    static func options(for library: Library) -> [LibrarySort] {
        let podcast = library.isPodcast
        return [
            LibrarySort(field: "media.metadata.title", descending: false, title: "Title A–Z"),
            LibrarySort(field: "media.metadata.title", descending: true, title: "Title Z–A"),
            LibrarySort(field: podcast ? "media.metadata.author" : "media.metadata.authorName", descending: false, title: "Author"),
            LibrarySort(field: "addedAt", descending: true, title: "Recently added")
        ]
    }
}

struct LibraryFilter: Hashable, Identifiable {
    let group: String
    let value: String
    let title: String
    var id: String { group + "." + value }

    /// Audiobookshelf filters are `group.base64(value)`. The server URL-decodes the value
    /// before base64 decoding, so `+` must survive the query string's space decoding.
    var parameter: String {
        group + "." + Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "%2B")
    }

    static let progress = [("not-started", "Not started"), ("in-progress", "In progress"), ("finished", "Finished")]
        .map { LibraryFilter(group: "progress", value: $0.0, title: $0.1) }
}

/// One library's server-side sorted, filtered, paginated catalog.
@MainActor final class LibraryBrowser: ObservableObject {
    static let pageSize = 60
    let library: Library
    private let api: APIClient
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var total = 0
    @Published private(set) var loading = false
    @Published private(set) var error: Error?
    @Published private(set) var sort: LibrarySort
    @Published private(set) var filter: LibraryFilter?
    @Published private(set) var filterData: LibraryFilters?
    private var nextPage = 0
    private var progressRevision: Int?
    private var generation = UUID()

    init(library: Library, api: APIClient) {
        self.library = library
        self.api = api
        sort = LibrarySort.options(for: library)[0]
    }

    var hasMore: Bool { items.count < total }
    var started: Bool { nextPage > 0 || loading }

    func reload() async {
        generation = UUID()
        items = []; total = 0; nextPage = 0; loading = false; error = nil
        await loadPage()
        if filterData == nil, !library.isPodcast { filterData = try? await api.filters(libraryID: library.id) }
    }

    func loadMore(after item: LibraryItem) async {
        guard hasMore, !loading, error == nil,
              let index = items.firstIndex(of: item), index >= items.count - 12 else { return }
        await loadPage()
    }

    func retry() async {
        error = nil
        if items.isEmpty { await reload() } else { await loadPage() }
    }

    /// Reloads progress-filtered results once listening progress has changed since they were fetched.
    func refresh(progressRevision revision: Int) async {
        defer { progressRevision = revision }
        guard let previous = progressRevision, previous != revision, filter?.group == "progress" else { return }
        await reload()
    }

    func apply(sort: LibrarySort) async {
        self.sort = sort
        await reload()
    }

    func apply(filter: LibraryFilter?) async {
        self.filter = filter
        await reload()
    }

    private func loadPage() async {
        let request = generation
        loading = true
        defer { if request == generation { loading = false } }
        do {
            let response = try await api.items(libraryID: library.id, page: nextPage, filter: filter?.parameter, sort: sort.field, descending: sort.descending)
            guard request == generation else { return }
            let known = Set(items.map(\.id))
            items += response.results.filter { !known.contains($0.id) }
            total = response.results.isEmpty ? items.count : response.total
            nextPage += 1
        } catch {
            guard request == generation, !(error is CancellationError) else { return }
            self.error = error
        }
    }
}
