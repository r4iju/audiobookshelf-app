import SwiftUI

/// Navigation owns its selection independently of the playback and account stores.
private enum ShellDestination: String, CaseIterable, Identifiable {
    case listenNow, library, downloads, search, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listenNow: return "Listen Now"
        case .library: return "Library"
        case .downloads: return "Downloads"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .listenNow: return "headphones"
        case .library: return "books.vertical"
        case .downloads: return "arrow.down.circle"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

struct NativeShell: View {
    @EnvironmentObject private var connection: ConnectionStore
    let library: Library
    var body: some View { NativeShellNavigation(api: connection.api, library: library) }
}

private struct NativeShellNavigation: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected = ShellDestination.library
    let api: APIClient
    let library: Library
    @StateObject private var search: LibrarySearchStore

    init(api: APIClient, library: Library) {
        self.api = api
        self.library = library
        _search = StateObject(wrappedValue: LibrarySearchStore(catalog: CatalogStore(api: api, library: library)))
    }

    var body: some View {
        shell.onReceive(connection.$screen) { screen in
            if case .shelf(let selectedLibrary) = screen {
                search.select(catalog: CatalogStore(api: api, library: selectedLibrary))
            }
        }
    }

    @ViewBuilder private var shell: some View {
        #if ABS_SDK_18
        if #available(iOS 18, *) {
            PlaybackContainer(content: adaptiveModernTabs, nativeTabAccessory: true)
        } else { legacyShell }
        #else
        legacyShell
        #endif
    }

    @ViewBuilder private var legacyShell: some View {
        if #available(iOS 16, *), UIDevice.current.userInterfaceIdiom == .pad {
            PlaybackContainer(content: NavigationSplitView {
                List {
                    ForEach(ShellDestination.allCases) { item in
                        Button { selected = item } label: { Label(l10n(item.title), systemImage: item.symbol) }
                    }
                }.listStyle(SidebarListStyle()).navigationTitle("Audiobook Loft")
            } detail: {
                // Keep the same native tab container when the sidebar collapses, so each stack survives selection changes.
                legacyTabs.toolbar(sizeClass == .regular ? .hidden : .visible, for: .tabBar)
            })
        } else {
            PlaybackContainer(content: legacyTabs)
        }
    }

    #if ABS_SDK_18
    @available(iOS 18, *) @ViewBuilder private var adaptiveModernTabs: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            searchableModernTabs.tabViewStyle(.sidebarAdaptable)
        } else {
            searchableModernTabs
        }
    }

    @available(iOS 18, *) @ViewBuilder private var searchableModernTabs: some View {
        #if ABS_SDK_26
        if #available(iOS 26, *) {
            modernTabs.tabViewSearchActivation(.searchTabSelection)
                .onChange(of: selected) { destination in
                    search.presented = destination == .search
                }
        } else {
            modernTabs
        }
        #else
        modernTabs
        #endif
    }

    @available(iOS 18, *) private var modernTabs: some View {
        TabView(selection: $selected) {
            Tab(l10n("Listen Now"), systemImage: "headphones", value: .listenNow) { destination(.listenNow) }
            Tab(l10n("Library"), systemImage: "books.vertical", value: .library) { destination(.library) }
            Tab(l10n("Downloads"), systemImage: "arrow.down.circle", value: .downloads) { destination(.downloads) }
            Tab(l10n("Settings"), systemImage: "gearshape", value: .settings) { destination(.settings) }
            Tab(value: .search, role: .search) { destination(.search) }
        }
    }

    #endif

    private var legacyTabs: some View {
        TabView(selection: $selected) {
            ForEach(ShellDestination.allCases) { item in
                destination(item).tabItem { Label(l10n(item.title), systemImage: item.symbol) }.tag(item)
            }
        }
    }

    @ViewBuilder private var searchDestination: some View {
        #if ABS_SDK_26
        if #available(iOS 26, *) {
            NativeNavigation { LibrarySearch(search: search, shellOwnsSearch: true).id(library.id) }
                .searchable(text: $search.query, isPresented: $search.presented, prompt: l10n("Books, podcasts, authors, series…"))
                .onSubmit(of: .search, search.submit)
        } else { legacySearchDestination }
        #else
        legacySearchDestination
        #endif
    }

    private var legacySearchDestination: some View {
        NativeNavigation { LibrarySearch(search: search).id(library.id) }
    }

    private func destination(_ item: ShellDestination) -> some View {
        destinationContent(item).modifier(NativePlaybackInset())
    }

    @ViewBuilder private func destinationContent(_ item: ShellDestination) -> some View {
        switch item {
        case .library:
            NativeNavigation { CatalogShelf(api: api, library: library) }.id(library.id)
        case .listenNow:
            NativeNavigation { CatalogShelf(api: api, library: library, listenNow: true) }.id(library.id)
        case .downloads: DownloadsView(embedded: true)
        case .search:
            searchDestination
        case .settings: NativeNavigation { NativeSettings() }
        }
    }
}

/// A contextual chooser never clears the stored library merely to open a sheet.
struct ShellLibraryChooser: View {
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.nativeStrings) private var l10n
    @Binding var presented: Bool
    @State private var libraries: [Library]?
    @State private var error: String?
    var body: some View {
        NativeNavigation {
            ShelfList {
                if let libraries {
                    ForEach(libraries) { library in
                        Button {
                            NativeHaptic.impact("library")
                            connection.select(library)
                            presented = false
                        } label: { Label(library.name, systemImage: library.mediaType == "podcast" ? "mic" : "books.vertical") }
                            .accessibilityIdentifier("library-" + library.id)
                    }
                } else if let error { RecoveryCard(message: error, retry: load) }
                else { ProgressView(l10n("Opening your library…")) }
            }.navigationTitle(l10n("Your libraries"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { presented = false } } }
        }.onAppear(perform: load)
    }
    private func load() {
        error = nil
        Task {
            do { libraries = try await connection.api.libraries() }
            catch { self.error = ConnectionStore.recovery(for: error) }
        }
    }
}
