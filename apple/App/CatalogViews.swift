import SwiftUI

struct ConnectedLibrary: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let library: Library
    var body: some View {
        Group {
            if #available(iOS 17, *), UIDevice.current.userInterfaceIdiom == .pad {
                AdaptiveLibraryNavigation(library: library, api: connection.api)
            } else if #available(iOS 16, *), sizeClass == .regular {
                NavigationSplitView {
                    LibrarySidebar(selected: library)
                } detail: {
                    NavigationStack { CatalogShelf(api: connection.api, library: library) }
                }.navigationSplitViewStyle(.balanced)
            } else if sizeClass == .regular {
                NavigationView {
                    LibrarySidebar(selected: library)
                    CatalogShelf(api: connection.api, library: library)
                }
            } else {
                NativeNavigation { CatalogShelf(api: connection.api, library: library) }
            }
        }.id(library.id)
    }
}

@available(iOS 17, *)
private struct AdaptiveLibraryNavigation: View {
    let library: Library
    let api: APIClient
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            LibrarySidebar(selected: library)
        } detail: {
            NavigationStack { CatalogShelf(api: api, library: library) }
        }.navigationSplitViewStyle(.balanced)
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.nativeStrings) private var l10n
    let selected: Library
    var body: some View {
        ShelfList {
            Label(selected.name, systemImage: selected.mediaType == "podcast" ? "mic" : "books.vertical")
                .foregroundColor(ShelfStyle.accent)
            Button(l10n("Change library")) { NativeHaptic.impact("library"); Task { await connection.openLibrariesForSelection() } }
            Button(l10n("Sign out")) { NativeHaptic.impact("sign-out"); connection.signOut() }
        }.listStyle(SidebarListStyle()).navigationTitle(l10n("Library"))
    }
}

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
    @State private var collectionsPresented = false
    @State private var playlistsPresented = false
    @State private var settingsPresented = false
    @State private var statisticsPresented = false
    @State private var diagnosticsPresented = false
    @Environment(\.nativeStrings) private var l10n
    init(api: APIClient, library: Library, filter: String? = nil) {
        _catalog = StateObject(wrappedValue: CatalogStore(api: api, library: library, filter: filter))
    }
    var body: some View {
        ScrollView {
            switch catalog.state {
            case .loading:
                ProgressView(l10n("Opening your books…")).frame(maxWidth: .infinity).padding(60)
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
                    HStack {
                        Text(l10n(catalog.library.mediaType == "podcast" ? "All podcasts" : "All books")).font(.title3.weight(.semibold))
                        Text("\(content.total)").font(.subheadline).foregroundColor(ShelfStyle.secondaryText)
                        Spacer()
                        Button { NativeHaptic.impact("layout"); listLayout.toggle() } label: { Image(systemName: listLayout ? "square.grid.2x2" : "list.bullet").frame(minWidth: 44, minHeight: 44) }
                            .nativeGlassButton()
                            .accessibilityLabel(l10n(listLayout ? "Show covers" : "Show list"))
                    }
                    if content.items.isEmpty {
                        Text(l10n(catalog.filter == nil ? "This library is empty. Add titles on your server, then refresh." : "No titles match this filter. Choose another filter to continue.")).foregroundColor(ShelfStyle.secondaryText)
                    }
                    LazyVGrid(columns: listLayout ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.adaptive(minimum: sizeCategory.isAccessibilityCategory ? 260 : 140, maximum: sizeCategory.isAccessibilityCategory ? 420 : 210), spacing: 16, alignment: .top)], spacing: 22) {
                        ForEach(content.items) { item in
                            NavigationLink(destination: BookDetails(item: item, catalog: catalog, progress: progress(item, content))) {
                                BookCard(item: item, catalog: catalog, listLayout: listLayout)
                            }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("book-\(item.id)")
                                .onAppear {
                                    if item.id == content.items.last?.id { Task { await catalog.loadMore() } }
                                }
                        }
                    }
                    if let error = content.pageError {
                        RecoveryCard(message: error) { Task { await catalog.loadMore() } }
                    } else if content.hasMore {
                        ProgressView().frame(maxWidth: .infinity).padding(20)

                    }
                }.padding(20).frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
        }.accessibilityIdentifier("catalog").background(appearance.background)
            .navigationTitle(catalog.library.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: LibrarySearch(catalog: catalog)) { Image(systemName: "magnifyingglass") }.accessibilityLabel(l10n("Search library"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Menu {
                            Button(l10n("Title A–Z")) { sort(.title, descending: false) }
                            Button(l10n("Title Z–A")) { sort(.title, descending: true) }
                            Button(l10n("Newest first")) { sort(.added, descending: true) }
                            Divider()
                            ForEach(CatalogSort.available(for: catalog.library.mediaType), id: \.self) { choice in Button(l10n(choice.name)) { sort(choice, descending: catalog.descending) } }
                            Button(l10n(catalog.descending ? "Ascending order" : "Descending order")) { sort(catalog.sort, descending: !catalog.descending) }
                        } label: { Image(systemName: "arrow.up.arrow.down").font(.body) }.accessibilityLabel(l10n("Sort library"))
                        Button { filterOptions = true } label: { Image(systemName: catalog.filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }.accessibilityLabel(l10n("Filter library"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if catalog.library.mediaType == "podcast", case .content(let content) = catalog.state, content.user.canManagePodcasts {
                            Button(l10n("Add podcast")) { addingPodcast = true }
                        }
                        Button(l10n("Settings")) { settingsPresented = true }
                        Button(l10n("Statistics")) { statisticsPresented = true }
                        Button(l10n("Downloads")) { downloads.presented = true }
                        if catalog.library.mediaType == "book" {
                            Button(l10n("Collections")) { collectionsPresented = true }
                        }
                        Button(l10n("Playlists")) { playlistsPresented = true }
                        Button(l10n("Diagnostics")) { diagnosticsPresented = true }
                        Button(l10n("Refresh")) { Task { await catalog.reload() } }
                        Button(l10n("Change library")) { NativeHaptic.impact("library"); Task { await connection.openLibrariesForSelection() } }
                        Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                        Button(l10n("Sign out")) { NativeHaptic.impact("sign-out"); connection.signOut() }.accessibilityIdentifier("account-signout")
                    } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel(l10n("Account")).accessibilityIdentifier("account")
                }
            }.onAppear { Task { if case .loading = catalog.state { await catalog.reload() } else { await catalog.refreshProgressIfNeeded() } } }
            .onReceive(realtime.events) { event in catalog.receive(event) }
            .sheet(isPresented: $filterOptions) { CatalogFilterOptions(catalog: catalog, presented: $filterOptions) }
            .sheet(isPresented: $addingPodcast) { AddPodcast(catalog: catalog, presented: $addingPodcast) }
            .catalogDestination(isPresented: $settingsPresented) { NativeSettings() }
            .catalogDestination(isPresented: $statisticsPresented) { StatisticsView(api: catalog.api) }
            .catalogDestination(isPresented: $diagnosticsPresented) { NativeDiagnosticsView() }
            .catalogDestination(isPresented: $collectionsPresented) { AudioGroupList(catalog: catalog, kind: .collection) }
            .catalogDestination(isPresented: $playlistsPresented) { AudioGroupList(catalog: catalog, kind: .playlist) }
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
                        Image(systemName: "book.closed.fill").font(.title2)
                        Text(item.title).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(3)
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
                    .padding(14).background(appearance.card).cornerRadius(18)
            } else { VStack(alignment: .leading, spacing: 12) { BookArtwork(item: item, catalog: catalog); labels } }
        }
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 5) {
            metadata(title, font: .subheadline.weight(.semibold), color: .primary)
            metadata(author.isEmpty ? l10n("Unknown author") : author, font: .caption, color: ShelfStyle.secondaryText)
            if let duration = item.media.duration { Text(ShelfTime.describe(duration)).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
        }
    }
    private func metadata(_ value: String, font: Font, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            if !listLayout {
                Text("Ag\nAg").hidden().accessibilityHidden(true)
            }
            Text(value).foregroundColor(color).lineLimit(sizeCategory.isAccessibilityCategory ? nil : 2)
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
                Text(author).font(.caption).foregroundColor(ShelfStyle.secondaryText).lineLimit(sizeCategory.isAccessibilityCategory ? nil : 1)
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
        let safe = seconds.isFinite ? Int(min(max(seconds, 0), Double(Int.max / 2))) : 0
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
