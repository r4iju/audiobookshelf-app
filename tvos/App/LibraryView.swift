import SwiftUI

struct LibraryView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    @StateObject private var browser: LibraryBrowser
    let chooseLibrary: () -> Void

    init(library: Library, api: APIClient, chooseLibrary: @escaping () -> Void) {
        self.chooseLibrary = chooseLibrary
        _browser = StateObject(wrappedValue: LibraryBrowser(library: library, api: api))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Button(action: chooseLibrary) {
                        Label(browser.library.name, systemImage: "chevron.down")
                    }
                    .accessibilityIdentifier("library-chooser")
                    .accessibilityLabel(browser.library.name)
                    .accessibilityHint(l10n("Choose library"))
                    Spacer()
                    if browser.total > 0 {
                        Text(browser.library.isPodcast ? (browser.total == 1 ? l10n("1 podcast") : l10n("{0} podcasts", browser.total)) : (browser.total == 1 ? l10n("1 title") : l10n("{0} titles", browser.total)))
                            .foregroundStyle(.secondary)
                    }
                }
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
                            .buttonBorderShape(.roundedRectangle(radius: 14))
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
        .task { if !browser.started { await browser.reload() } }
        .onAppear { Task { await browser.refresh(progressRevision: catalog.progressRevision) } }
        .onChange(of: catalog.progressRevision) { Task { await browser.refresh(progressRevision: catalog.progressRevision) } }
    }

    private var controls: some View {
        HStack(spacing: 30) {
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

/// Selection belongs to Library, while the native tab bar stays independent of server configuration.
struct LibraryDestination: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.nativeStrings) private var l10n
    @State private var selectedID: String?
    @State private var choosing = false
    @State private var pendingSelectionID: String?
    @State private var path: [Route] = []

    private var selected: Library? {
        catalog.libraries.first { $0.id == selectedID } ?? catalog.libraries.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let library = selected {
                    LibraryView(library: library, api: catalog.api) { choosing = true }
                        .id(library.id)
                } else if let error = catalog.catalogError {
                    StatusMessage(text: error) { Task { await catalog.loadCatalog() } }
                } else if catalog.loadingCatalog {
                    ProgressView(l10n("Loading…"))
                } else {
                    Text(l10n("This library is empty.")).foregroundStyle(.secondary)
                }
            }
            .catalogRoutes()
        }
        .sheet(isPresented: $choosing, onDismiss: {
            if let pendingSelectionID {
                path.removeAll()
                selectedID = pendingSelectionID
                self.pendingSelectionID = nil
            }
        }) {
            NavigationStack {
                List(catalog.libraries) { library in
                    Button {
                        pendingSelectionID = library.id
                        choosing = false
                    } label: {
                        HStack(spacing: 24) {
                            Label(library.name, systemImage: library.isPodcast ? "mic" : "books.vertical")
                            Spacer()
                            if library.id == selected?.id { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("library-choice-\(library.id)")
                    .accessibilityLabel(library.name)
                    .accessibilityAddTraits(library.id == selected?.id ? [.isSelected] : [])
                }
                .navigationTitle(l10n("Choose library"))
            }
            .tvLocalization()
        }
        .onChange(of: catalog.accountID) { selectedID = nil; pendingSelectionID = nil; choosing = false; path.removeAll() }
    }
}
