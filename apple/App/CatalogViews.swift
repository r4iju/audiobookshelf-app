import SwiftUI

struct ConnectedLibrary: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let library: Library
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationView {
                    LibrarySidebar(selected: library)
                    CatalogShelf(api: connection.api, library: library)
                }
            } else {
                NavigationView { CatalogShelf(api: connection.api, library: library) }
                    .navigationViewStyle(StackNavigationViewStyle())
            }
        }.id(library.id)
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    let selected: Library
    var body: some View {
        List {
            Label("Audiobookshelf", systemImage: "books.vertical.fill").font(.title2.bold()).padding(.vertical, 18)
            Label(selected.name, systemImage: selected.mediaType == "podcast" ? "mic" : "books.vertical")
                .foregroundColor(ShelfStyle.accent)
            Button("Change library") { Task { await connection.openLibrariesForSelection() } }
            Button("Sign out") { connection.signOut() }
        }.listStyle(SidebarListStyle()).navigationTitle("Library")
    }
}

struct CatalogShelf: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    @StateObject private var catalog: CatalogStore
    @State private var listLayout = false
    @State private var filterOptions = false
    @State private var addingPodcast = false
    @State private var collectionsPresented = false
    @State private var playlistsPresented = false
    init(api: APIClient, library: Library, filter: String? = nil) {
        _catalog = StateObject(wrappedValue: CatalogStore(api: api, library: library, filter: filter))
    }
    var body: some View {
        ScrollView {
            switch catalog.state {
            case .loading:
                ProgressView("Opening your books…").frame(maxWidth: .infinity).padding(60)
            case .failed(let error):
                RecoveryCard(message: error) { Task { await catalog.reload() } }.padding(24)
            case .content(let content):
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A little more listening.").font(.system(.largeTitle, design: .serif).bold())
                        Text("Find a familiar voice. Discover a new world.").foregroundColor(.secondary)
                    }.padding(.top, 8)
                    if !content.continuing.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Continue listening").font(.title2.bold())
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
                        Text("All \(catalog.library.mediaType == "podcast" ? "podcasts" : "books")").font(.title2.bold())
                        Text("\(content.total)").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button { listLayout.toggle() } label: { Image(systemName: listLayout ? "square.grid.2x2" : "list.bullet").padding(10) }
                            .accessibilityLabel(listLayout ? "Show covers" : "Show list")
                    }
                    if content.items.isEmpty {
                        Text(catalog.filter == nil ? "This library is empty. Add titles on your server, then refresh." : "No titles match this filter. Choose another filter to continue.").foregroundColor(.secondary)
                    }
                    LazyVGrid(columns: listLayout ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 20)], spacing: 26) {
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
                }.padding(24).frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
        }.accessibilityIdentifier("catalog").background(ShelfStyle.background)
            .navigationTitle(catalog.library.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: LibrarySearch(catalog: catalog)) { Image(systemName: "magnifyingglass").font(.title2) }.accessibilityLabel("Search library")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Menu {
                            Button("Title A–Z") { Task { await catalog.changeSort(.title, descending: false) } }
                            Button("Title Z–A") { Task { await catalog.changeSort(.title, descending: true) } }
                            Button("Newest first") { Task { await catalog.changeSort(.added, descending: true) } }
                            Divider()
                            ForEach(CatalogSort.available(for: catalog.library.mediaType), id: \.self) { sort in Button(sort.name) { Task { await catalog.changeSort(sort, descending: catalog.descending) } } }
                            Button(catalog.descending ? "Ascending order" : "Descending order") { Task { await catalog.changeSort(catalog.sort, descending: !catalog.descending) } }
                        } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort library")
                        Button { filterOptions = true } label: { Image(systemName: catalog.filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }.accessibilityLabel("Filter library")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if catalog.library.mediaType == "podcast", case .content(let content) = catalog.state, content.user.canManagePodcasts {
                            Button("Add podcast") { addingPodcast = true }
                        }
                        Button("Downloads") { downloads.presented = true }
                        if catalog.library.mediaType == "book" {
                            Button("Collections") { collectionsPresented = true }
                        }
                        Button("Playlists") { playlistsPresented = true }
                        Button("Refresh") { Task { await catalog.reload() } }
                        Button("Change library") { Task { await connection.openLibrariesForSelection() } }
                        Button("Saved connections") { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                        Button("Sign out") { connection.signOut() }.accessibilityIdentifier("account-signout")
                    } label: { Image(systemName: "person.crop.circle").font(.title2) }.accessibilityIdentifier("account")
                }
            }.onAppear { if case .loading = catalog.state { Task { await catalog.reload() } } }
            .sheet(isPresented: $filterOptions) { CatalogFilterOptions(catalog: catalog, presented: $filterOptions) }
            .sheet(isPresented: $addingPodcast) { AddPodcast(catalog: catalog, presented: $addingPodcast) }
            .background(NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .collection), isActive: $collectionsPresented) { EmptyView() })
            .background(NavigationLink(destination: AudioGroupList(catalog: catalog, kind: .playlist), isActive: $playlistsPresented) { EmptyView() })
    }

    private func progress(_ item: LibraryItem, _ content: CatalogStore.Catalog) -> MediaProgress? {
        content.user.mediaProgress.first { $0.libraryItemId == item.id && $0.episodeId == nil }
    }
}

struct BookArtwork: View {
    let item: LibraryItem
    let catalog: CatalogStore
    @State private var image: UIImage?
    @State private var request: Task<Void, Never>?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(ShelfStyle.card)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed.fill").font(.largeTitle)
                    Text(item.title).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(3)
                }.foregroundColor(ShelfStyle.accent).padding(18)
            }
        }.aspectRatio(0.72, contentMode: .fit).clipped().cornerRadius(16)
            .accessibilityHidden(true)
            .onAppear { if image == nil { request = Task { image = await catalog.artwork(for: item) } } }
            .onDisappear { request?.cancel(); request = nil }
    }
}

struct BookCard: View {
    let item: LibraryItem
    let catalog: CatalogStore
    let listLayout: Bool
    var body: some View {
        Group {
            if listLayout {
                HStack(spacing: 18) { BookArtwork(item: item, catalog: catalog).frame(width: 62); labels; Spacer() }
                    .padding(14).background(ShelfStyle.card).cornerRadius(18)
            } else { VStack(alignment: .leading, spacing: 12) { BookArtwork(item: item, catalog: catalog); labels } }
        }
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.headline).foregroundColor(.primary).lineLimit(3)
            Text(item.author.isEmpty ? "Unknown author" : item.author).font(.caption).foregroundColor(.secondary).lineLimit(2)
            if let duration = item.media.duration { Text(ShelfTime.describe(duration)).font(.caption).foregroundColor(.secondary) }
        }
    }
}

struct ContinueCard: View {
    let item: LibraryItem
    let catalog: CatalogStore
    let progress: MediaProgress?
    var body: some View {
        HStack(spacing: 18) {
            BookArtwork(item: item, catalog: catalog).frame(width: 74)
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title).font(.headline).foregroundColor(.primary).lineLimit(2)
                Text(item.author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                ProgressView(value: progress?.fraction ?? 0).accentColor(ShelfStyle.accent)
                Text("\(Int((progress?.fraction ?? 0) * 100))% listened").font(.caption).foregroundColor(.secondary)
            }.frame(width: 175, alignment: .leading)
        }.padding(18).background(ShelfStyle.card).cornerRadius(24)
    }
}

struct RecoveryCard: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Couldn't open this part of your library", systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).font(.callout).foregroundColor(.secondary)
            Button("Try again", action: retry)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(ShelfStyle.card).cornerRadius(20)
    }
}

enum ShelfTime {
    static func describe(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? Int(min(max(seconds, 0), Double(Int.max / 2))) : 0
        if safe < 60 { return "\(safe) sec" }
        if safe < 3600 { return "\(safe / 60) min" }
        return "\(safe / 3600) hr \((safe % 3600) / 60) min"
    }
}
