import SwiftUI

enum CatalogSort: String, CaseIterable {
    case title = "media.metadata.title", author = "media.metadata.authorName", authorLast = "media.metadata.authorNameLF"
    case year = "media.metadata.publishedYear", added = "addedAt", size, duration = "media.duration"
    case fileCreated = "birthtimeMs", fileModified = "mtimeMs", progress, started = "progress.createdAt", finished = "progress.finishedAt", random
    case podcastAuthor = "media.metadata.author", episodes = "media.numTracks"
    static func available(for mediaType: String) -> [CatalogSort] {
        if mediaType == "podcast" { return [.title, .podcastAuthor, .added, .size, .episodes, .fileCreated, .fileModified, .random] }
        return allCases.filter { $0 != .podcastAuthor && $0 != .episodes }
    }
    var name: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author, first name"
        case .authorLast: return "Author, last name"
        case .year: return "Published year"
        case .added: return "Date added"
        case .size: return "File size"
        case .duration: return "Duration"
        case .fileCreated: return "File created"
        case .fileModified: return "File modified"
        case .progress: return "Listening progress"
        case .started: return "Date started"
        case .finished: return "Date finished"
        case .random: return "Random"
        case .podcastAuthor: return "Author"
        case .episodes: return "Number of episodes"
        }
    }
}

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
    /// The account this catalog was loaded for; changes for any other account never reach it.
    private var owner: AccountIdentity?
    /// One realtime refresh runs at a time. The next one waits, and a queued items reload is never downgraded.
    private var refreshing = false
    private var queuedRefresh: (event: NativeRealtime.Event, items: Bool)?
    /// Item updates (`nil` item for a removal) received while catalog requests were in flight, numbered in arrival order,
    /// so a response that predates a change cannot undo it.
    private var itemChanges: [(sequence: Int, id: String, item: LibraryItem?)] = []
    private var changeSequence = 0
    private var requestsInFlight = 0
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
        owner = api.signIn?.account
        state = .loading
        let since = beginRequest(); defer { endRequest() }
        do {
            async let response = api.items(libraryID: library.id, page: 0, filter: filter, sort: sort.rawValue, descending: descending)
            async let user = api.me()
            async let personalized = api.personalized(libraryID: library.id)
            let (items, account, shelves) = try await (response, user, personalized)
            guard generation == request else { return }
            page = 0
            needsProgressRefresh = false
            let first = merged(items.results, since: since)
            state = .content(Catalog(items: first.items, total: items.total - first.removed, user: account, continuing: continuing(shelves, since: since)))
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
        let since = beginRequest(); defer { endRequest() }
        do {
            let response = try await api.items(libraryID: library.id, page: page + 1, filter: filter, sort: sort.rawValue, descending: descending)
            guard generation == request, case .content(let latest) = state else { return }
            catalog = latest
            let existing = Set(catalog.items.map(\.id))
            let fresh = response.results.filter { !existing.contains($0.id) }
            let next = merged(fresh, since: since)
            catalog.items += next.items
            catalog.total = response.total - next.removed
            if !fresh.isEmpty || !catalog.hasMore { page += 1 }
            if fresh.isEmpty && catalog.hasMore {
                catalog.pageError = NativeStrings.current("The server returned no more books. Refresh the library to try again.")
            }
        } catch {
            guard generation == request, case .content(let latest) = state else { return }
            catalog = latest
            catalog.pageError = ConnectionStore.recovery(for: error)
        }
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

    /// Applies the user after a progress reset; Continue Listening keeps items without progress
    /// otherwise, so the reset book or episode is removed explicitly.
    func discardProgress(_ user: CurrentUser, itemID: String, episodeID: String?) {
        applyProgress(user)
        guard case .content(var content) = state, content.user.id == user.id else { return }
        content.continuing.removeAll { $0.id == itemID && $0.recentEpisode?.id == episodeID }
        state = .content(content)
    }

    func refreshProgressIfNeeded() async {
        guard needsProgressRefresh, case .content(var current) = state, !current.loadingMore else { return }
        let request = generation
        current.loadingMore = true; current.pageError = nil
        state = .content(current)
        let since = beginRequest(); defer { endRequest() }
        do {
            let response = try await api.items(libraryID: library.id, page: 0, filter: filter, sort: sort.rawValue, descending: descending)
            guard generation == request, case .content(var content) = state else { return }
            let first = merged(response.results, since: since)
            content.items = first.items; content.total = response.total - first.removed
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

    /// Whether `event` belongs to this catalog: received by the current sign-in of the account the catalog was loaded for.
    /// Screens opened from the catalog check it before acting on a change and again before publishing what they fetched.
    func owns(_ event: NativeRealtime.Event) -> Bool { event.isCurrent(on: api) && event.account == owner }

    /// Applies a change another client made to this catalog's account, keeping the visible catalog in place.
    func receive(_ event: NativeRealtime.Event) {
        guard owns(event) else { return }
        switch event.change {
        case .authenticated: refresh(items: true, for: event)
        case .progress, .user: refresh(items: filter?.hasPrefix("progress.") == true, for: event)
        case .itemsAdded(let libraries) where libraries.contains(library.id): refresh(items: true, for: event)
        case .itemsUpdated(let updated): change(updated.map { ($0.id, $0) }, for: event)
        case .itemRemoved(let id): change([(id, nil)], for: event)
        default: break
        }
    }

    private func change(_ changes: [(id: String, item: LibraryItem?)], for event: NativeRealtime.Event) {
        changeSequence += 1
        if requestsInFlight > 0 { itemChanges += changes.map { (changeSequence, $0.id, $0.item) } }
        guard case .content(var content) = state else { return }
        let listed = merged(content.items, with: changes)
        content.items = listed.items
        content.continuing = merged(content.continuing, with: changes).items
        content.total = max(content.total - listed.removed, 0)
        state = .content(content)
        // Pages are offsets into the server's list, so removing a listed book shifts every page not loaded yet.
        if listed.removed > 0 && content.hasMore { refresh(items: true, for: event) }
    }

    private func refresh(items: Bool, for event: NativeRealtime.Event) {
        guard !refreshing else {
            queuedRefresh = (event, items || queuedRefresh?.items == true)
            return
        }
        refreshing = true
        Task {
            await refreshNow(items: items, for: event)
            refreshing = false
            if let next = queuedRefresh { queuedRefresh = nil; refresh(items: next.items, for: next.event) }
        }
    }

    /// Reloading items supersedes page loading; a progress-only refresh leaves loaded and loading pages alone. A progress
    /// filter's membership follows progress, so `receive` reloads its items instead.
    private func refreshNow(items reloadItems: Bool, for event: NativeRealtime.Event) async {
        guard owns(event) else { return }
        if reloadItems { generation = UUID() }
        let pages = generation
        defer {
            if reloadItems, generation == pages, case .content(var content) = state, content.loadingMore {
                content.loadingMore = false
                state = .content(content)
            }
        }
        let since = beginRequest(); defer { endRequest() }
        do {
            async let user = api.me()
            async let personalized = api.personalized(libraryID: library.id)
            let firstPage = reloadItems ? try await api.items(libraryID: library.id, page: 0, filter: filter, sort: sort.rawValue, descending: descending) : nil
            let (account, shelves) = try await (user, personalized)
            guard generation == pages, owns(event) else { return }
            var content: Catalog
            if case .content(let current) = state { content = current; content.user = account }
            else if reloadItems { content = Catalog(items: [], total: 0, user: account, continuing: []) }
            else { return }
            content.continuing = continuing(shelves, since: since)
            if let firstPage {
                let first = merged(firstPage.results, since: since)
                content.items = first.items; content.total = firstPage.total - first.removed; content.pageError = nil; content.loadingMore = false
                page = 0; needsProgressRefresh = false
            }
            state = .content(content)
        } catch {
            // A visible catalog stays usable; the next change, reconnection or manual refresh retries. One that this
            // refresh superseded while loading has nothing to show.
            guard reloadItems, generation == pages, owns(event), case .loading = state else { return }
            state = .failed(ConnectionStore.recovery(for: error))
        }
    }

    private func continuing(_ shelves: [PersonalizedShelf], since sequence: Int) -> [LibraryItem] {
        filter == nil ? merged(shelves.filter { $0.id == "continue-listening" }.flatMap(\.entities), since: sequence).items : []
    }

    private func beginRequest() -> Int { requestsInFlight += 1; return changeSequence }
    private func endRequest() {
        requestsInFlight -= 1
        if requestsInFlight == 0 { itemChanges.removeAll() }
    }

    /// `items` as a request that started at `sequence` should publish them, with every item change received since applied.
    private func merged(_ items: [LibraryItem], since sequence: Int) -> (items: [LibraryItem], removed: Int) {
        merged(items, with: itemChanges.filter { $0.sequence > sequence }.map { ($0.id, $0.item) })
    }

    private func merged(_ items: [LibraryItem], with changes: [(id: String, item: LibraryItem?)]) -> (items: [LibraryItem], removed: Int) {
        guard !changes.isEmpty else { return (items, 0) }
        var latest: [String: LibraryItem?] = [:]
        for change in changes { latest[change.id] = change.item }
        let result = items.compactMap { item in latest[item.id] ?? item }
        return (result, items.count - result.count)
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
