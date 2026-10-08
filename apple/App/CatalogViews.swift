import SwiftUI

struct CatalogShelf: View {
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var realtime: NativeRealtime
    @StateObject private var catalog: CatalogStore
    @AppStorage("previewListLayout") private var listLayout = false
    @State private var filterOptions = false
    @State private var addingPodcast = false
    @State private var libraryChooser = false
    @Environment(\.nativeStrings) private var l10n
    let listenNow: Bool
    init(api: APIClient, library: Library, filter: String? = nil, listenNow: Bool = false) {
        self.listenNow = listenNow
        _catalog = StateObject(wrappedValue: CatalogStore(api: api, library: library, filter: filter))
    }
    var body: some View {
        Group {
            if listLayout, case .content(let content) = catalog.state, !listenNow {
                list(content)
            } else { grid }
        }.accessibilityIdentifier("catalog").background(appearance.background)
            .navigationTitle(listenNow ? l10n("Listen Now") : catalog.library.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !listenNow {
                        Button { libraryChooser = true } label: { Label(l10n("Change library"), systemImage: "books.vertical") }.accessibilityLabel(l10n("Change library"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !listenNow { HStack {
                        Menu {
                            Button(l10n("Title A–Z")) { sort(.title, descending: false) }
                            Button(l10n("Title Z–A")) { sort(.title, descending: true) }
                            Button(l10n("Newest first")) { sort(.added, descending: true) }
                            Divider()
                            ForEach(CatalogSort.available(for: catalog.library.mediaType), id: \.self) { choice in Button(l10n(choice.name)) { sort(choice, descending: catalog.descending) } }
                            Button(l10n(catalog.descending ? "Ascending order" : "Descending order")) { sort(catalog.sort, descending: !catalog.descending) }
                        } label: { Image(systemName: "arrow.up.arrow.down").font(.body) }.accessibilityLabel(l10n("Sort library"))
                        Button { filterOptions = true } label: { Image(systemName: catalog.filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }.accessibilityLabel(l10n("Filter library"))
                    } }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if catalog.library.mediaType == "podcast", case .content(let content) = catalog.state, content.user.canManagePodcasts {
                            Button(l10n("Add podcast")) { addingPodcast = true }
                        }
                        Button(l10n("Refresh")) { Task { await catalog.reload() } }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel(l10n("Library actions"))
                }
            }.onAppear { Task { if case .loading = catalog.state { await catalog.reload() } else { await catalog.refreshProgressIfNeeded() } } }
            .onReceive(realtime.events) { event in catalog.receive(event) }
            .sheet(isPresented: $filterOptions) { CatalogFilterOptions(catalog: catalog, presented: $filterOptions) }
            .sheet(isPresented: $addingPodcast) { AddPodcast(catalog: catalog, presented: $addingPodcast) }
            .sheet(isPresented: $libraryChooser) { ShellLibraryChooser(presented: $libraryChooser) }

    }

    private var grid: some View {
        ScrollView {
            switch catalog.state {
            case .loading:
                CatalogStatus(title: l10n("Opening your books…"), message: catalog.library.name, symbol: "books.vertical", loading: true).padding(24)
            case .failed(let error):
                RecoveryCard(message: error) { Task { await catalog.reload() } }.padding(24)
            case .content(let content):
                VStack(alignment: .leading, spacing: 30) {
                    if !content.continuing.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(l10n("Continue listening")).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(content.continuing) { item in
                                        NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: progress(item, content))) {
                                            ContinueCard(item: item, catalog: catalog, progress: progress(item, content))
                                        }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("continue-\(item.id)")
                                    }
                                }
                            }
                        }
                    }
                    if listenNow && content.continuing.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(l10n("Your next listen"), systemImage: "headphones").font(.title2.bold())
                            Text(l10n("Choose a title from your library to start listening.")).foregroundColor(ShelfStyle.secondaryText)
                        }
                    }
                    if !listenNow {
                        HStack(spacing: 20) {
                            if catalog.library.mediaType == "book" {
                                NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .collection)) { Label(l10n("Collections"), systemImage: "square.stack") }
                            }
                            NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .playlist)) { Label(l10n("Playlists"), systemImage: "music.note.list") }
                        }.font(.subheadline.weight(.semibold)).padding(.vertical, 4)
                    }
                    HStack {
                        Text(l10n(listenNow ? "From your library" : catalog.library.mediaType == "podcast" ? "All podcasts" : "All books")).font(.title3.weight(.semibold))
                        if !listenNow { Text("\(content.total)").font(.subheadline).foregroundColor(ShelfStyle.secondaryText) }
                        Spacer()
                        if !listenNow { Button { NativeHaptic.impact("layout"); listLayout.toggle() } label: { Image(systemName: listLayout ? "square.grid.2x2" : "list.bullet").frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(l10n(listLayout ? "Show covers" : "Show list")) }
                    }
                    if content.items.isEmpty {
                        CatalogStatus(title: l10n(catalog.filter == nil ? "This library is empty. Add titles on your server, then refresh." : "No titles match this filter. Choose another filter to continue."), message: catalog.library.name, symbol: "books.vertical")
                    }
                    LazyVGrid(columns: listLayout ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.adaptive(minimum: sizeCategory.isAccessibilityCategory ? 260 : 140, maximum: sizeCategory.isAccessibilityCategory ? 420 : 210), spacing: 16, alignment: .top)], spacing: 22) {
                        ForEach(listenNow ? Array(content.items.prefix(6)) : content.items) { item in
                            NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: progress(item, content))) {
                                BookCard(item: item, catalog: catalog, listLayout: listLayout)
                            }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("book-\(item.id)")
                                .onAppear {
                                    if !listenNow && item.id == content.items.last?.id { Task { await catalog.loadMore() } }
                                }
                        }
                    }
                    if !listenNow, let error = content.pageError {
                        RecoveryCard(message: error) { Task { await catalog.loadMore() } }
                    } else if !listenNow && content.hasMore {
                        ProgressView().frame(maxWidth: .infinity).padding(20)

                    }
                }.padding(20).frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
        }
    }

    private func list(_ content: CatalogStore.Catalog) -> some View {
        ShelfList {
            if !content.continuing.isEmpty {
                Section(header: Text(l10n("Continue listening"))) {
                    ForEach(content.continuing) { item in
                        NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: progress(item, content))) {
                            HStack(spacing: 14) {
                                BookArtwork(item: item, catalog: catalog).frame(width: 62)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.body.weight(.semibold)).foregroundColor(.primary)
                                    Text(item.author.isEmpty ? l10n("Unknown author") : item.author).font(.subheadline).foregroundColor(ShelfStyle.secondaryText)
                                    ProgressView(value: progress(item, content)?.fraction ?? 0)
                                    Text(l10n("{0}% listened", Int((progress(item, content)?.fraction ?? 0) * 100))).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                                }
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("continue-\(item.id)")
                    }
                }
            }
            Section {
                if catalog.library.mediaType == "book" {
                    NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .collection)) { Label(l10n("Collections"), systemImage: "square.stack") }
                }
                NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .playlist)) { Label(l10n("Playlists"), systemImage: "music.note.list") }
            }
            Section(header: HStack {
                Text(l10n(catalog.library.mediaType == "podcast" ? "All podcasts" : "All books"))
                Text("\(content.total)")
                Spacer()
                Button { NativeHaptic.impact("layout"); listLayout.toggle() } label: { Image(systemName: "square.grid.2x2").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(PlainButtonStyle()).accessibilityLabel(l10n("Show covers"))
            }) {
                if content.items.isEmpty {
                    CatalogStatus(title: l10n(catalog.filter == nil ? "This library is empty. Add titles on your server, then refresh." : "No titles match this filter. Choose another filter to continue."), message: catalog.library.name, symbol: "books.vertical")
                }
                ForEach(content.items) { item in
                    NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: progress(item, content))) {
                        BookCard(item: item, catalog: catalog, listLayout: true)
                    }.accessibilityIdentifier("book-\(item.id)")
                        .onAppear { if item.id == content.items.last?.id { Task { await catalog.loadMore() } } }
                }
                if let error = content.pageError { RecoveryCard(message: error) { Task { await catalog.loadMore() } } }
                else if content.hasMore { ProgressView().frame(maxWidth: .infinity).padding(20) }
            }
        }
    }

    private func sort(_ choice: CatalogSort, descending: Bool) {
        NativeHaptic.impact("sort")
        Task { await catalog.changeSort(choice, descending: descending) }
    }

    private func progress(_ item: LibraryItem, _ content: CatalogStore.Catalog) -> MediaProgress? {
        content.user.mediaProgress.first { $0.libraryItemId == item.id && $0.episodeId == nil }
    }
}

struct BookArtwork: View {
    @Environment(\.shelfAppearance) private var appearance
    let item: LibraryItem
    let catalog: CatalogStore
    @State private var image: UIImage?
    @State private var request: Task<Void, Never>?
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(image == nil ? appearance.card : .clear)
            .aspectRatio(1, contentMode: .fit)
            .overlay(Group {
                if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                else {
                    VStack(spacing: 8) {
                        Image(systemName: item.mediaType == "podcast" ? "mic.fill" : "book.closed.fill").font(.title2)
                    }.foregroundColor(ShelfStyle.accent).padding(12)
                }
            })
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            .onAppear { if image == nil { request = Task { image = await catalog.artwork(for: item) } } }
            .onDisappear { request?.cancel(); request = nil }
    }
}

struct BookCard: View {
    @Environment(\.shelfAppearance) private var appearance
    @Environment(\.nativeStrings) private var l10n
    let item: LibraryItem
    let catalog: CatalogStore
    let listLayout: Bool
    @Environment(\.sizeCategory) private var sizeCategory
    /// `LibraryItem` equality compares ids only, so metadata edited elsewhere is held separately for SwiftUI to redraw it.
    private let title: String
    private let author: String
    init(item: LibraryItem, catalog: CatalogStore, listLayout: Bool) {
        self.item = item; self.catalog = catalog; self.listLayout = listLayout
        title = item.title; author = item.author
    }
    var body: some View {
        Group {
            if listLayout {
                HStack(spacing: 18) { BookArtwork(item: item, catalog: catalog).frame(width: 62); labels; Spacer() }
                    .padding(.vertical, 6)
            } else { VStack(alignment: .leading, spacing: 12) { BookArtwork(item: item, catalog: catalog); labels } }
        }
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 5) {
            metadata(title, font: listLayout ? .body.weight(.semibold) : .subheadline.weight(.semibold), color: .primary)
            metadata(author.isEmpty ? l10n("Unknown author") : author, font: listLayout ? .subheadline : .caption, color: ShelfStyle.secondaryText)
            if let duration = item.media.duration { Text(ShelfTime.describe(duration)).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
        }
    }
    private func metadata(_ value: String, font: Font, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            if !listLayout {
                Text("Ag\nAg").hidden().accessibilityHidden(true)
            }
            Text(value).foregroundColor(color).lineLimit(listLayout || sizeCategory.isAccessibilityCategory ? nil : 2)
        }.font(font).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContinueCard: View {
    @Environment(\.shelfAppearance) private var appearance
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.sizeCategory) private var sizeCategory
    let item: LibraryItem
    let catalog: CatalogStore
    let progress: MediaProgress?
    /// Held separately for the same reason as in `BookCard`.
    private let title: String
    private let author: String
    init(item: LibraryItem, catalog: CatalogStore, progress: MediaProgress?) {
        self.item = item; self.catalog = catalog; self.progress = progress
        title = item.title; author = item.author
    }
    var body: some View {
        HStack(spacing: 14) {
            BookArtwork(item: item, catalog: catalog).frame(width: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(sizeCategory.isAccessibilityCategory ? nil : 2)
                Text(author.isEmpty ? l10n("Unknown author") : author).font(.caption).foregroundColor(ShelfStyle.secondaryText).lineLimit(sizeCategory.isAccessibilityCategory ? nil : 1)
                ProgressView(value: progress?.fraction ?? 0).accentColor(ShelfStyle.accent)
                Text(l10n("{0}% listened", Int((progress?.fraction ?? 0) * 100))).font(.caption).foregroundColor(ShelfStyle.secondaryText)
            }.frame(width: sizeCategory.isAccessibilityCategory ? 260 : 175, alignment: .leading)
        }.padding(16).background(appearance.card).cornerRadius(18)
    }
}

struct RecoveryCard: View {
    @Environment(\.shelfAppearance) private var appearance
    @Environment(\.nativeStrings) private var l10n
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(l10n("Couldn't open this part of your library"), systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).font(.callout).foregroundColor(ShelfStyle.secondaryText)
            Button(l10n("Try again"), action: retry)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(appearance.card).cornerRadius(20)
    }
}

enum ShelfTime {
    static func describe(_ seconds: Double, language: NativeLanguage = NativeStrings.current.language) -> String {
        // Unrepresentable metadata is unavailable, rather than a saturated invented duration.
        // The authoritative duration is retained by the media/player stores.
        guard seconds.isFinite, seconds < Double(Int.max / 2) else {
            let strings = NativeStrings(language: language)
            return strings("Duration unavailable")
        }
        let safe = Int(max(seconds, 0))
        if language != .english { return localized(safe, locale: language.locale) }
        if safe < 60 { return "\(safe) sec" }
        if safe < 3600 { return "\(safe / 60) min" }
        return "\(safe / 3600) hr \((safe % 3600) / 60) min"
    }
    /// Other languages use the system's abbreviated units, which follow the same seconds, minutes, then hours and minutes steps.
    private static func localized(_ safe: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = safe < 60 ? [.second] : safe < 3600 ? [.minute] : [.hour, .minute]
        formatter.zeroFormattingBehavior = safe < 3600 ? .default : .dropLeading
        return formatter.string(from: TimeInterval(safe - (safe >= 60 ? safe % 60 : 0))) ?? "\(safe)"
    }
}

struct CatalogStatus: View {
    let title: String
    let message: String
    let symbol: String
    var loading = false
    var body: some View {
        VStack(spacing: 14) {
            if loading { ProgressView() }
            else { Image(systemName: symbol).font(.largeTitle).foregroundColor(ShelfStyle.secondaryText).accessibilityHidden(true) }
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundColor(ShelfStyle.secondaryText).multilineTextAlignment(.center)
        }.padding(.vertical, 28).frame(maxWidth: 520).frame(maxWidth: .infinity)
    }
}
