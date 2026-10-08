import SwiftUI

/// An author in the current library: bio, image, series and every title, as the server reports them.
struct RelatedAuthorView: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    let catalog: CatalogStore
    let name: String
    @StateObject private var page: RelatedAuthor
    @State private var image: UIImage?
    @State private var started = false

    init(catalog: CatalogStore, authorID: String, name: String) {
        self.catalog = catalog
        self.name = name
        _page = StateObject(wrappedValue: RelatedAuthor(api: catalog.api, id: authorID, libraryID: catalog.library.id))
    }

    var body: some View {
        ShelfList {
            Section {
                HStack(alignment: .center, spacing: 18) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill().accessibilityIdentifier("author-image")
                        } else {
                            Image(systemName: "person.fill").font(.system(size: 40)).foregroundColor(ShelfStyle.secondaryText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(appearance.card)
                        }
                    }
                    .frame(width: 96, height: 96).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.author?.name ?? name).font(.title2.weight(.semibold)).accessibilityIdentifier("author-name")
                        if page.books.total > 0 {
                            Text(page.books.total == 1 ? l10n("1 title") : l10n("{0} titles", page.books.total)).font(.subheadline).foregroundColor(ShelfStyle.secondaryText)
                                .accessibilityIdentifier("author-count")
                        }
                    }
                }
                if let bio = page.author?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    Text(bio).font(.callout).foregroundColor(ShelfStyle.secondaryText).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 720, alignment: .leading)
                        .accessibilityIdentifier("author-bio")
                }
                if let failure = page.failure {
                    RecoveryCard(message: ConnectionStore.recovery(for: failure)) { Task { await page.load() } }
                }
            }
            if !page.series.isEmpty {
                Section(header: Text(l10n("Series"))) {
                    ForEach(page.series) { series in
                        NavigationLink(destination: RelatedSeriesView(catalog: catalog, seriesID: series.id, name: series.name)) {
                            HStack {
                                Text(series.name).foregroundColor(.primary)
                                Spacer()
                                if let books = series.books { Text("\(books.count)").foregroundColor(ShelfStyle.secondaryText) }
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("author-series." + series.id)
                    }
                }
            }
            if !page.books.items.isEmpty {
                Section(header: Text(l10n("Titles"))) {
                    ForEach(page.books.items) { item in
                        NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: nil)) {
                            BookCard(item: item, catalog: catalog, listLayout: true)
                        }.accessibilityIdentifier("author-book." + item.id)
                            .onAppear { Task { await page.books.loadMore(after: item) } }
                    }
                }
            }
            if page.books.loading { ProgressView(l10n("Opening your books…")).frame(maxWidth: .infinity).padding(.vertical, 20) }
            if !page.books.loading, page.failure == nil, page.books.error == nil, page.books.items.isEmpty {
                CatalogStatus(title: l10n("Titles"), message: l10n("This library is empty. Add titles on your server, then refresh."), symbol: "books.vertical")
            }
            if let error = page.books.error, !page.books.items.isEmpty {
                RecoveryCard(message: ConnectionStore.recovery(for: error)) { Task { await page.load() } }
            }
        }
        .background(appearance.background).navigationTitle(page.author?.name ?? name).navigationBarTitleDisplayMode(.inline)
        .onAppear { if !started { started = true; Task { await page.load() } } }
        .onReceive(page.$imageData) { data in image = data.flatMap(UIImage.init(data:)) }
    }
}

/// A series in the current library, with its books in the server's sequence order.
struct RelatedSeriesView: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    let catalog: CatalogStore
    let name: String
    @StateObject private var page: RelatedSeries
    @State private var started = false

    init(catalog: CatalogStore, seriesID: String, name: String) {
        self.catalog = catalog
        self.name = name
        _page = StateObject(wrappedValue: RelatedSeries(api: catalog.api, id: seriesID, libraryID: catalog.library.id))
    }

    private var progressSummary: String? {
        guard let series = page.series else { return nil }
        let count = series.progress?.libraryItemIds.count ?? page.books.total
        let titles = count == 1 ? l10n("1 book") : l10n("{0} books", count)
        guard let progress = series.progress else { return titles }
        return l10n("{0} · {1} finished", titles, progress.libraryItemIdsFinished.count)
    }

    var body: some View {
        ShelfList {
            Section {
                Text(page.series?.name ?? name).font(.title2.weight(.semibold)).accessibilityIdentifier("series-name")
                if let summary = progressSummary {
                    Text(summary).font(.subheadline).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier("series-progress")
                }
                if let description = page.series?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description).font(.callout).foregroundColor(ShelfStyle.secondaryText).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 720, alignment: .leading)
                        .accessibilityIdentifier("series-description")
                }
                if let failure = page.failure {
                    RecoveryCard(message: ConnectionStore.recovery(for: failure)) { Task { await page.load() } }
                }
            }
            Section(header: Text(l10n("Titles"))) {
                ForEach(page.books.items) { item in
                    NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: nil)) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let sequence = page.sequence(of: item) {
                                Text(l10n("Book {0}", sequence)).font(.caption.weight(.semibold)).foregroundColor(ShelfStyle.secondaryText)
                                    .accessibilityIdentifier("series-sequence." + item.id)
                            }
                            BookCard(item: item, catalog: catalog, listLayout: true)
                        }
                    }.accessibilityIdentifier("series-book." + item.id)
                        .onAppear { Task { await page.books.loadMore(after: item) } }
                }
                if page.books.loading { ProgressView(l10n("Opening your books…")).frame(maxWidth: .infinity).padding(.vertical, 20) }
                if !page.books.loading, page.failure == nil, page.books.error == nil, page.books.items.isEmpty {
                    CatalogStatus(title: l10n("Titles"), message: l10n("This library is empty. Add titles on your server, then refresh."), symbol: "books.vertical")
                }
                if let error = page.books.error, !page.books.items.isEmpty {
                    RecoveryCard(message: ConnectionStore.recovery(for: error)) { Task { await page.load() } }
                }
            }
        }
        .background(appearance.background).navigationTitle(page.series?.name ?? name).navigationBarTitleDisplayMode(.inline)
        .onAppear { if !started { started = true; Task { await page.load() } } }
    }
}

/// Links from a book's details to each of its series, with its place in it, and to each author.
/// It keeps only the derived links: `LibraryItem` equality is by id, so holding the item would hide the expanded item's series.
struct RelatedBookLinks: View {
    @Environment(\.nativeStrings) private var l10n
    struct AuthorLink: Hashable { let id: String; let name: String }
    let catalog: CatalogStore
    private let series: [SeriesReference]
    private let authors: [AuthorLink]

    init(item: LibraryItem, catalog: CatalogStore) {
        self.catalog = catalog
        series = item.series
        authors = (item.media.metadata.authors ?? []).compactMap { author in author.id.map { AuthorLink(id: $0, name: author.name) } }
    }

    var body: some View {
        Group {
            if !series.isEmpty {
                Section(header: Text(l10n("Series"))) {
                    ForEach(series, id: \.self) { series in
                        NavigationLink(destination: RelatedSeriesView(catalog: catalog, seriesID: series.id, name: series.name)) {
                            Label(series.sequence.map { l10n("{0} · Book {1}", series.name, $0) } ?? series.name, systemImage: "books.vertical")
                        }
                        .accessibilityIdentifier("detail-series." + series.id)
                        .accessibilityLabel(series.sequence.map { l10n("{0}, book {1}", series.name, $0) } ?? series.name)
                    }
                }
            }
            if !authors.isEmpty {
                Section(header: Text(l10n("Authors"))) {
                    ForEach(authors, id: \.self) { author in
                        NavigationLink(destination: RelatedAuthorView(catalog: catalog, authorID: author.id, name: author.name)) {
                            Label(author.name, systemImage: "person")
                        }.accessibilityIdentifier("detail-author." + author.id)
                    }
                }
            }
        }
    }
}
