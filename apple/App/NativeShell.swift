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
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected = ShellDestination.library
    let library: Library

    var body: some View {
        if #available(iOS 18, *) {
            PlaybackContainer(content: modernTabs, nativeTabAccessory: true)
        } else if #available(iOS 16, *), UIDevice.current.userInterfaceIdiom == .pad {
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

    @available(iOS 18, *) private var modernTabs: some View {
        TabView(selection: $selected) {
            Tab(l10n("Listen Now"), systemImage: "headphones", value: .listenNow) { destination(.listenNow) }
            Tab(l10n("Library"), systemImage: "books.vertical", value: .library) { destination(.library) }
            Tab(l10n("Downloads"), systemImage: "arrow.down.circle", value: .downloads) { destination(.downloads) }
            Tab(l10n("Search"), systemImage: "magnifyingglass", value: .search, role: .search) { destination(.search) }
            Tab(l10n("Settings"), systemImage: "gearshape", value: .settings) { destination(.settings) }
        }.tabViewStyle(.sidebarAdaptable)
    }

    private var legacyTabs: some View {
        TabView(selection: $selected) {
            ForEach(ShellDestination.allCases) { item in
                destination(item).tabItem { Label(l10n(item.title), systemImage: item.symbol) }.tag(item)
            }
        }
    }

    @ViewBuilder private func destination(_ item: ShellDestination) -> some View {
        switch item {
        case .library:
            NativeNavigation { CatalogShelf(api: connection.api, library: library).id(library.id) }
        case .listenNow:
            NativeNavigation { CatalogShelf(api: connection.api, library: library, listenNow: true).id(library.id) }
        case .downloads: DownloadsView(embedded: true)
        case .search:
            NativeNavigation { LibrarySearch(catalog: CatalogStore(api: connection.api, library: library)).id(library.id) }
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
