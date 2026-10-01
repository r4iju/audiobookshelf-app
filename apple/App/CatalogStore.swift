import SwiftUI

@MainActor final class CatalogStore: ObservableObject {
    struct Catalog {
        var items: [LibraryItem]
        var total: Int
        var user: CurrentUser
        var continuing: [LibraryItem]
        var loadingMore = false
        var pageError: String?
        var hasMore: Bool { items.count < total }
    }
    enum State {
        case loading
        case content(Catalog)
        case failed(String)
    }
    @Published private(set) var state: State = .loading
    let api: APIClient
    let library: Library
    @Published private(set) var filter: String?
    @Published private(set) var sort: CatalogSort = .title
    @Published private(set) var descending = false
    private var needsProgressRefresh = false
    private var page = 0
    private var generation = UUID()
    private let covers = NSCache<NSString, UIImage>()

    init(api: APIClient, library: Library, filter: String? = nil) {
        self.api = api
        self.library = library
        self.filter = filter
        covers.countLimit = 150
    }

    func reload() async {
        let request = UUID()
        generation = request
        state = .loading
        do {
            async let response = api.items(libraryID: library.id, page: 0, filter: filter, sort: sort.rawValue, descending: descending)
            async let user = api.me()
            async let personalized = api.personalized(libraryID: library.id)
            let (items, account, shelves) = try await (response, user, personalized)
            guard generation == request else { return }
            page = 0
            needsProgressRefresh = false
            state = .content(Catalog(items: items.results, total: items.total, user: account, continuing: filter == nil ? shelves.filter { $0.id == "continue-listening" }.flatMap(\.entities) : []))
        } catch {
            guard generation == request else { return }
            state = .failed(ConnectionStore.recovery(for: error))
        }
    }

    func loadMore() async {
        if needsProgressRefresh { await refreshProgressIfNeeded(); return }
        guard case .content(var catalog) = state, !catalog.loadingMore, catalog.hasMore else { return }
        let request = generation
        catalog.loadingMore = true
        catalog.pageError = nil
        state = .content(catalog)
        do {
            let response = try await api.items(libraryID: library.id, page: page + 1, filter: filter, sort: sort.rawValue, descending: descending)
            guard generation == request else { return }
            let existing = Set(catalog.items.map(\.id))
            let newItems = response.results.filter { !existing.contains($0.id) }
            catalog.items += newItems
            catalog.total = response.total
            if !newItems.isEmpty || !catalog.hasMore { page += 1 }
            if newItems.isEmpty && catalog.hasMore {
                catalog.pageError = "The server returned no more books. Refresh the library to try again."
            }
        } catch {
            guard generation == request else { return }
            catalog.pageError = ConnectionStore.recovery(for: error)
        }
        if case .content(let latest) = state { catalog.user = latest.user; catalog.continuing = latest.continuing }
        catalog.loadingMore = false
        state = .content(catalog)
    }

    func applyProgress(_ user: CurrentUser) {
        guard case .content(var content) = state, content.user.id == user.id else { return }
        generation = UUID()
        content.loadingMore = false
        content.user = user
        if filter?.hasPrefix("progress.") == true { needsProgressRefresh = true }
        content.continuing.removeAll { item in
            guard let progress = user.mediaProgress.first(where: { $0.libraryItemId == item.id && $0.episodeId == nil }) else { return false }
            return progress.isFinished == true || (progress.currentTime ?? 0) <= 0
        }
        state = .content(content)
    }

    func refreshProgressIfNeeded() async {
        guard needsProgressRefresh, case .content(var current) = state, !current.loadingMore else { return }
        let request = generation
        current.loadingMore = true; current.pageError = nil
        state = .content(current)
        do {
            let response = try await api.items(libraryID: library.id, page: 0, filter: filter, sort: sort.rawValue, descending: descending)
            guard generation == request, case .content(var content) = state else { return }
            content.items = response.results; content.total = response.total
            content.pageError = nil; content.loadingMore = false
            page = 0; needsProgressRefresh = false
            state = .content(content)
        } catch {
            guard generation == request, case .content(var content) = state else { return }
            content.loadingMore = false
            content.pageError = ConnectionStore.recovery(for: error)
            state = .content(content)
        }
    }

    func artwork(for item: LibraryItem) async -> UIImage? {
        if let cached = covers.object(forKey: item.id as NSString) { return cached }
        guard let data = try? await api.coverData(itemID: item.id), !Task.isCancelled, let image = UIImage(data: data) else { return nil }
        covers.setObject(image, forKey: item.id as NSString)
        return image
    }

    func changeSort(_ field: CatalogSort, descending: Bool) async {
        sort = field; self.descending = descending
        await reload()
    }
    func changeFilter(_ value: String?) async { filter = value; await reload() }
}
