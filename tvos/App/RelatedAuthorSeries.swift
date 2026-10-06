import SwiftUI

/// An author or series as found in one library, whose catalog its page queries.
struct RelatedLink: Hashable {
    let id: String
    let name: String
    let libraryID: String
}

extension Route {
    var relatedIdentifier: String? {
        switch self {
        case .author(let author): "author." + author.id
        case .series(let series): "series." + series.id
        default: nil
        }
    }
}

struct RelatedLabel: View {
    let route: Route

    var body: some View {
        switch route {
        case .author(let author): Label(author.name, systemImage: "person.fill")
        case .series(let series): Label(series.name, systemImage: "books.vertical.fill")
        default: EmptyView()
        }
    }
}

/// The links from a book's details to each of its series and authors.
/// It keeps only the derived links: `LibraryItem` equality is by id, so holding the item would hide the expanded item's series.
struct RelatedLinks: View {
    @Environment(\.nativeStrings) private var l10n
    private let series: [(reference: SeriesReference, link: RelatedLink)]
    private let authors: [RelatedLink]

    init(item: LibraryItem) {
        let libraryID = item.libraryId
        series = libraryID.map { library in item.series.map { (reference: $0, link: RelatedLink(id: $0.id, name: $0.name, libraryID: library)) } } ?? []
        authors = libraryID.map { library in
            (item.media.metadata.authors ?? []).compactMap { author in author.id.map { RelatedLink(id: $0, name: author.name, libraryID: library) } }
        } ?? []
    }

    var body: some View {
        if !series.isEmpty || !authors.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 30) {
                    ForEach(series, id: \.link) { series in
                        let reference = series.reference
                        NavigationLink(value: Route.series(series.link)) {
                            Label(reference.sequence.map { l10n("{0} · Book {1}", reference.name, $0) } ?? reference.name, systemImage: "books.vertical.fill")
                        }
                        .accessibilityIdentifier("detail-series." + reference.id)
                        .accessibilityLabel(reference.sequence.map { l10n("{0}, book {1}", reference.name, $0) } ?? reference.name)
                    }
                    ForEach(authors, id: \.self) { author in
                        NavigationLink(value: Route.author(author)) { Label(author.name, systemImage: "person.fill") }
                            .accessibilityIdentifier("detail-author." + author.id)
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

struct AuthorView: View {
    @EnvironmentObject private var catalog: CatalogStore
    let author: RelatedLink

    var body: some View { AuthorScreen(author: author, catalog: catalog) }
}

private struct AuthorScreen: View {
    @Environment(\.nativeStrings) private var l10n
    let author: RelatedLink
    let catalog: CatalogStore
    @StateObject private var page: RelatedAuthor
    @State private var image: UIImage?

    init(author: RelatedLink, catalog: CatalogStore) {
        self.author = author
        self.catalog = catalog
        _page = StateObject(wrappedValue: RelatedAuthor(api: catalog.api, id: author.id, libraryID: author.libraryID))
    }

    var body: some View {
        let books = page.books
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                HStack(alignment: .top, spacing: 60) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill().accessibilityIdentifier("author-image")
                        } else {
                            Image(systemName: "person.fill").font(.system(size: 120)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
                        }
                    }
                    .frame(width: 300, height: 300).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 18) {
                        Text(page.author?.name ?? author.name).font(.system(size: 52, weight: .bold)).accessibilityIdentifier("author-name")
                        if books.total > 0 {
                            Text(books.total == 1 ? l10n("1 title") : l10n("{0} titles", books.total)).font(.headline).accessibilityIdentifier("author-count")
                        }
                        if let bio = page.author?.description.map(Format.plainText), !bio.isEmpty {
                            Text(bio).foregroundStyle(.secondary).lineLimit(6).accessibilityIdentifier("author-bio")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = page.failure {
                    StatusMessage(text: CatalogStore.recovery(for: error), identifier: "related-error", retryIdentifier: "retry-related") { Task { await load() } }
                }
                if !page.series.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n("Series")).font(.title3.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 30) {
                                ForEach(page.series) { series in
                                    NavigationLink(value: Route.series(RelatedLink(id: series.id, name: series.name, libraryID: author.libraryID))) {
                                        Label(series.name + (series.books.map { " · \($0.count)" } ?? ""), systemImage: "books.vertical.fill")
                                    }
                                    .accessibilityIdentifier("author-series." + series.id)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
                if !books.items.isEmpty {
                    Text(l10n("Titles")).font(.title3.bold())
                    LazyVGrid(columns: TileGrid.columns, alignment: .leading, spacing: 56) {
                        ForEach(books.items) { item in
                            NavigationLink(value: Route.to(item)) { ItemTile(item: item) }
                                .buttonStyle(.card)
                                .buttonBorderShape(.roundedRectangle(radius: 14))
                                .accessibilityIdentifier("author-book." + item.id)
                                .onAppear { Task { await books.loadMore(after: item) } }
                        }
                    }
                    .focusSection()
                }
                if books.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = books.error, !books.items.isEmpty {
                    StatusMessage(text: CatalogStore.recovery(for: error), identifier: "related-error", retryIdentifier: "retry-related") { Task { await load() } }
                }
            }
            .padding(80)
        }
        .task { if page.author == nil { await load() } }
        .onReceive(page.$imageData) { data in image = data.flatMap(UIImage.init(data:)) }
    }

    private func load() async {
        await page.load()
        if let failure = page.failure { catalog.noteAuthentication(failure) }
    }
}

struct SeriesView: View {
    @EnvironmentObject private var catalog: CatalogStore
    let series: RelatedLink

    var body: some View { SeriesScreen(series: series, catalog: catalog) }
}

private struct SeriesScreen: View {
    @Environment(\.nativeStrings) private var l10n
    let series: RelatedLink
    let catalog: CatalogStore
    @StateObject private var page: RelatedSeries

    private var progressSummary: String? {
        guard let counts = page.counts else { return nil }
        let books = counts.books == 1 ? l10n("1 book") : l10n("{0} books", counts.books)
        return counts.finished.map { l10n("{0} · {1} finished", books, $0) } ?? books
    }

    init(series: RelatedLink, catalog: CatalogStore) {
        self.series = series
        self.catalog = catalog
        _page = StateObject(wrappedValue: RelatedSeries(api: catalog.api, id: series.id, libraryID: series.libraryID))
    }

    var body: some View {
        let books = page.books
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(page.series?.name ?? series.name).font(.system(size: 52, weight: .bold)).accessibilityIdentifier("series-name")
                    if let progress = progressSummary { Text(progress).font(.headline).accessibilityIdentifier("series-progress") }
                    if let description = page.series?.description.map(Format.plainText), !description.isEmpty {
                        Text(description).foregroundStyle(.secondary).lineLimit(6).accessibilityIdentifier("series-description")
                    }
                }
                if let error = page.failure {
                    StatusMessage(text: CatalogStore.recovery(for: error), identifier: "related-error", retryIdentifier: "retry-related") { Task { await load() } }
                }
                LazyVGrid(columns: TileGrid.columns, alignment: .leading, spacing: 56) {
                    ForEach(books.items) { item in
                        VStack(alignment: .leading, spacing: 30) {
                            if let sequence = page.sequence(of: item) {
                                Text(l10n("Book {0}", sequence)).font(.headline).accessibilityIdentifier("series-sequence." + item.id)
                            }
                            NavigationLink(value: Route.to(item)) { ItemTile(item: item) }
                                .buttonStyle(.card)
                                .buttonBorderShape(.roundedRectangle(radius: 14))
                                .accessibilityIdentifier("series-book." + item.id)
                                .onAppear { Task { await books.loadMore(after: item) } }
                        }
                    }
                }
                .focusSection()
                if books.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = books.error, !books.items.isEmpty {
                    StatusMessage(text: CatalogStore.recovery(for: error), identifier: "related-error", retryIdentifier: "retry-related") { Task { await load() } }
                }
            }
            .padding(80)
        }
        .task { if page.series == nil { await load() } }
    }

    private func load() async {
        await page.load()
        if let failure = page.failure { catalog.noteAuthentication(failure) }
    }
}
