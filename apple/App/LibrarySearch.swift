import SwiftUI
import UIKit

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
        systemSearch
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
    @ViewBuilder private var systemSearch: some View {
        if #available(iOS 15, *) {
            results.searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: l10n("Books, podcasts, authors, series…"))
                .onSubmit(of: .search, submit)
        } else {
            results.background(LegacyNavigationSearch(query: $search.query, prompt: l10n("Books, podcasts, authors, series…"), submit: submit).frame(width: 0, height: 0))
        }
    }
    private var results: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text(search.catalog.library.name).font(.subheadline.weight(.semibold)).foregroundColor(ShelfStyle.secondaryText)
                    switch search.state {
                    case .idle: Text(l10n("Find your next listen.")).foregroundColor(ShelfStyle.secondaryText)
                    case .loading: ProgressView(l10n("Searching your library…")).frame(maxWidth: .infinity)
                    case .failed(let error): RecoveryCard(message: error) { submit() }
                    case .results(let results):
                        if results.isEmpty { Text(l10n("No results. Try another title, author, or series.")).foregroundColor(ShelfStyle.secondaryText) }
                        if !results.items.isEmpty { Text(l10n(search.catalog.library.mediaType == "podcast" ? "Podcasts" : "Books")).font(.headline) }
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
                                        Text(result.libraryItem.title).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(appearance.card).cornerRadius(16)
                                }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("search-episode-\(episode.id)")
                            }
                        }
                        if !(results.authors ?? []).isEmpty { Text(l10n("Authors")).font(.headline) }
                        ForEach(results.authors ?? []) { author in
                            relatedRow(author.name, identifier: "search-author-" + author.id, destination: RelatedAuthorView(catalog: search.catalog, authorID: author.id, name: author.name))
                        }
                        if !(results.series ?? []).isEmpty { Text(l10n("Series")).font(.headline) }
                        ForEach(results.series ?? []) { series in
                            relatedRow(series.series.name, identifier: "search-series-" + series.id, destination: RelatedSeriesView(catalog: search.catalog, seriesID: series.id, name: series.series.name))
                        }
                        if !(results.narrators ?? []).isEmpty { Text(l10n("Narrators")).font(.headline) }
                        ForEach(results.narrators ?? []) { narrator in related(narrator.name, group: "narrators", value: narrator.name) }
                        if !(results.tags ?? []).isEmpty { Text(l10n("Tags")).font(.headline) }
                        ForEach(results.tags ?? []) { tag in related(tag.name, group: "tags", value: tag.name) }
                        if search.canShowMore(results) { Button(l10n("Show more results")) { Task { await search.search(more: true) } } }
                    }
                }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(appearance.background).navigationTitle(l10n("Search"))
    }
    private func submit() { pending?.cancel(); pending = Task { await search.search() } }
    private func related(_ name: String, group: String, value: String) -> some View {
        relatedRow(name, identifier: "search-\(group)-\(value)", destination: CatalogShelf(api: search.catalog.api, library: search.catalog.library, filter: group + "." + Data(value.utf8).base64EncodedString()))
    }
    private func relatedRow<Destination: View>(_ name: String, identifier: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack { Text(name); Spacer(); Image(systemName: "chevron.right") }.padding(18).background(appearance.card).cornerRadius(16)
        }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier(identifier)
    }
}

/// On iOS 14 the navigation controller, rather than an embedded fixed-height bar, owns search.
private struct LegacyNavigationSearch: UIViewControllerRepresentable {
    @Binding var query: String
    let prompt: String
    let submit: () -> Void
    func makeUIViewController(context: Context) -> SearchBridge { SearchBridge() }
    func updateUIViewController(_ controller: SearchBridge, context: Context) {
        controller.queryChanged = { query = $0 }
        controller.submitted = submit
        controller.search.searchBar.placeholder = prompt
        if controller.search.searchBar.text != query { controller.search.searchBar.text = query }
        controller.attach()
    }
    final class SearchBridge: UIViewController, UISearchResultsUpdating, UISearchBarDelegate {
        let search = UISearchController(searchResultsController: nil)
        var queryChanged: ((String) -> Void)?
        var submitted: (() -> Void)?
        override func viewDidLoad() {
            super.viewDidLoad()
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.delegate = self
            search.searchBar.searchTextField.accessibilityIdentifier = "library-search"
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let navigation = self.navigationController else { return }
                navigation.topViewController?.navigationItem.searchController = self.search
                navigation.topViewController?.navigationItem.hidesSearchBarWhenScrolling = false
            }
        }
        func updateSearchResults(for searchController: UISearchController) { queryChanged?(searchController.searchBar.text ?? "") }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder(); submitted?() }
    }
}
