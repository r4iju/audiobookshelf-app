import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @StateObject private var browser: LibraryBrowser
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 260), spacing: 48, alignment: .top)]

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
                        Text(browser.filter == nil ? "This library is empty." : "No titles match this filter.")
                            .font(.title3).foregroundStyle(.secondary).padding(60)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
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
    }

    private var controls: some View {
        HStack(spacing: 30) {
            Text(browser.library.name).font(.title2.bold())
            if browser.total > 0 {
                Text("\(browser.total) \(browser.library.mediaType == "podcast" ? "podcasts" : "titles")").foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(LibrarySort.options(for: browser.library)) { option in
                    Button(option.title) { Task { await browser.apply(sort: option) } }
                }
            } label: { Label("Sort: \(browser.sort.title)", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("library-sort")
                .accessibilityLabel("Sort: \(browser.sort.title)")
            if browser.library.mediaType == "book" {
                Menu {
                    Button("All titles") { Task { await browser.apply(filter: nil) } }
                    Section("Progress") { options(LibraryFilter.progress) }
                    if let genres = browser.filterData?.genres, !genres.isEmpty {
                        Section("Genre") { options(genres.map { LibraryFilter(group: "genres", value: $0, title: $0) }) }
                    }
                    if let narrators = browser.filterData?.narrators, !narrators.isEmpty {
                        Section("Narrator") { options(narrators.map { LibraryFilter(group: "narrators", value: $0, title: $0) }) }
                    }
                    if let authors = browser.filterData?.authors, !authors.isEmpty {
                        Section("Author") { options(authors.map { LibraryFilter(group: "authors", value: $0.id, title: $0.name) }) }
                    }
                } label: { Label(filterTitle, systemImage: "line.3.horizontal.decrease") }
                    .accessibilityIdentifier("library-filter")
                    .accessibilityLabel(filterTitle)
            }
        }
    }

    private var filterTitle: String { browser.filter.map { "Filter: \($0.title)" } ?? "Filter" }

    private func options(_ filters: [LibraryFilter]) -> some View {
        ForEach(filters) { filter in
            Button(filter.title) { Task { await browser.apply(filter: filter) } }
        }
    }
}
