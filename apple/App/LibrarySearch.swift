import SwiftUI

@MainActor final class LibrarySearchStore: ObservableObject {
    enum State { case idle, loading, results(SearchResponse), failed(String) }
    @Published private(set) var state: State = .idle
    @Published var query = ""
    private var generation = UUID()
    private var limit = 12
    let catalog: CatalogStore
    init(catalog: CatalogStore) { self.catalog = catalog }

    func search(more: Bool = false) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = UUID()
        generation = request
        guard !text.isEmpty else { state = .idle; return }
        limit = more ? limit + 12 : 12
        state = .loading
        do {
            let result = try await catalog.api.search(libraryID: catalog.library.id, query: text, limit: limit)
            guard generation == request else { return }
            state = .results(result)
        } catch { if generation == request { state = .failed(ConnectionStore.recovery(for: error)) } }
    }
    func canShowMore(_ response: SearchResponse) -> Bool { response.items.count >= limit || (response.episodes ?? []).count >= limit }
}

struct LibrarySearch: View {
    @Environment(\.shelfAppearance) private var appearance
    @StateObject private var search: LibrarySearchStore
    @State private var pending: Task<Void, Never>?
    @Environment(\.nativeStrings) private var l10n
    init(catalog: CatalogStore) { _search = StateObject(wrappedValue: LibrarySearchStore(catalog: catalog)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(l10n("Books, podcasts, authors, series…"), text: $search.query, onCommit: { submit() })
                    .accessibilityIdentifier("library-search")
                if !search.query.isEmpty { Button { search.query = ""; submit() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(l10n("Clear search")) }
            }.padding(14).background(appearance.card).cornerRadius(16).padding(20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    switch search.state {
                    case .idle: Text(l10n("Find your next listen.")).foregroundColor(.secondary)
                    case .loading: ProgressView(l10n("Searching your library…")).frame(maxWidth: .infinity)
                    case .failed(let error): RecoveryCard(message: error) { submit() }
                    case .results(let results):
                        if results.isEmpty { Text(l10n("No results. Try another title, author, or series.")).foregroundColor(.secondary) }
                        ForEach(results.items) { item in
                            NavigationLink(destination: BookDetails(item: item, catalog: search.catalog, progress: nil)) {
                                BookCard(item: item, catalog: search.catalog, listLayout: true)
                            }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("search-\(item.id)")
                        }
                        if !(results.episodes ?? []).isEmpty { Text(l10n("Episodes")).font(.headline) }
                        ForEach(results.episodes ?? []) { result in
                            if let episode = result.libraryItem.recentEpisode {
                                NavigationLink(destination: BookDetails(item: result.libraryItem, catalog: search.catalog, progress: nil, episode: episode)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(episode.title).font(.headline).foregroundColor(.primary)
                                        Text(result.libraryItem.title).font(.caption).foregroundColor(.secondary)
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(appearance.card).cornerRadius(16)
                                }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("search-episode-\(episode.id)")
                            }
                        }
                        if !(results.authors ?? []).isEmpty { Text(l10n("Authors")).font(.headline) }
                        ForEach(results.authors ?? []) { author in related(author.name, group: "authors", value: author.id) }
                        if !(results.series ?? []).isEmpty { Text(l10n("Series")).font(.headline) }
                        ForEach(results.series ?? []) { series in related(series.series.name, group: "series", value: series.id) }
                        if !(results.narrators ?? []).isEmpty { Text(l10n("Narrators")).font(.headline) }
                        ForEach(results.narrators ?? []) { narrator in related(narrator.name, group: "narrators", value: narrator.name) }
                        if !(results.tags ?? []).isEmpty { Text(l10n("Tags")).font(.headline) }
                        ForEach(results.tags ?? []) { tag in related(tag.name, group: "tags", value: tag.name) }
                        if search.canShowMore(results) { Button(l10n("Show more results")) { Task { await search.search(more: true) } } }
                    }
                }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(appearance.background).navigationTitle(l10n("Search"))
            .onChange(of: search.query) { _ in
                pending?.cancel()
                pending = Task {
                    do { try await Task.sleep(nanoseconds: 350_000_000) }
                    catch { return }
                    await search.search()
                }
            }
            .onDisappear { pending?.cancel() }
    }
    private func submit() { pending?.cancel(); pending = Task { await search.search() } }
    private func related(_ name: String, group: String, value: String) -> some View {
        NavigationLink(destination: CatalogShelf(api: search.catalog.api, library: search.catalog.library, filter: group + "." + Data(value.utf8).base64EncodedString())) {
            HStack { Text(name); Spacer(); Image(systemName: "chevron.right") }.padding(18).background(appearance.card).cornerRadius(16)
        }.buttonStyle(PlainButtonStyle())
    }
}
