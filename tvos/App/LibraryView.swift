import SwiftUI

struct LibraryView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    @StateObject private var browser: LibraryBrowser

    init(library: Library, api: APIClient) {
        _browser = StateObject(wrappedValue: LibraryBrowser(library: library, api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    controls.focusSection()
                    if let error = browser.error, browser.items.isEmpty {
                        StatusMessage(text: CatalogStore.recovery(for: error)) { Task { await browser.retry() } }
                    } else if browser.items.isEmpty && !browser.loading && browser.started {
                        Text(browser.filter == nil ? l10n("This library is empty.") : l10n("No titles match this filter."))
                            .font(.title3).foregroundStyle(.secondary).padding(60)
                    }
                    LazyVGrid(columns: TileGrid.columns, alignment: .leading, spacing: 56) {
                        ForEach(browser.items) { item in
                            NavigationLink(value: Route.item(item)) { ItemTile(item: item) }
                                .buttonStyle(.card)
                                .accessibilityIdentifier("item-\(item.id)")
                                .onAppear { Task { await browser.loadMore(after: item) } }
                        }
                    }
                    .focusSection()
                    if browser.loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error = browser.error, !browser.items.isEmpty {
                        StatusMessage(text: CatalogStore.recovery(for: error)) { Task { await browser.retry() } }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .catalogRoutes()
        }
        .task { if !browser.started { await browser.reload() } }
        .onAppear { Task { await browser.refresh(progressRevision: catalog.progressRevision) } }
        .onChange(of: catalog.progressRevision) { Task { await browser.refresh(progressRevision: catalog.progressRevision) } }
    }

    private var controls: some View {
        HStack(spacing: 30) {
            Text(browser.library.name).font(.title2.bold())
            if browser.total > 0 {
                Text(browser.library.isPodcast ? l10n("{0} podcasts", browser.total) : l10n("{0} titles", browser.total)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(LibrarySort.options(for: browser.library)) { option in
                    Button(l10n(option.title)) { Task { await browser.apply(sort: option) } }
                }
            } label: { Label(l10n("Sort: {0}", l10n(browser.sort.title)), systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("library-sort")
                .accessibilityLabel(l10n("Sort: {0}", l10n(browser.sort.title)))
            if !browser.library.isPodcast {
                Menu {
                    Button(l10n("All titles")) { Task { await browser.apply(filter: nil) } }
                    Section(l10n("Progress")) { options(LibraryFilter.progress) }
                    if let genres = browser.filterData?.genres, !genres.isEmpty {
                        Section(l10n("Genre")) { options(genres.map { LibraryFilter(group: "genres", value: $0, title: $0) }) }
                    }
                    if let narrators = browser.filterData?.narrators, !narrators.isEmpty {
                        Section(l10n("Narrator")) { options(narrators.map { LibraryFilter(group: "narrators", value: $0, title: $0) }) }
                    }
                    if let authors = browser.filterData?.authors, !authors.isEmpty {
                        Section(l10n("Author")) { options(authors.map { LibraryFilter(group: "authors", value: $0.id, title: $0.name) }) }
                    }
                } label: { Label(filterTitle, systemImage: "line.3.horizontal.decrease") }
                    .accessibilityIdentifier("library-filter")
                    .accessibilityLabel(filterTitle)
            }
        }
    }

    /// Progress filters are app wording; genre, narrator and author filters show the server's names.
    private var filterTitle: String { browser.filter.map { l10n("Filter: {0}", $0.group == "progress" ? l10n($0.title) : $0.title) } ?? l10n("Filter") }

    private func options(_ filters: [LibraryFilter]) -> some View {
        ForEach(filters) { filter in
            Button(filter.group == "progress" ? l10n(filter.title) : filter.title) { Task { await browser.apply(filter: filter) } }
        }
    }
}
