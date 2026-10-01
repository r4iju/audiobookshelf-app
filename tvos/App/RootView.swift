import SwiftUI

enum TVTab: Hashable {
    case home, library(String), search, nowPlaying, settings
}

@MainActor final class TVNavigator: ObservableObject {
    @Published var tab = TVTab.home
}

struct RootView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.nativeStrings) private var l10n
    @StateObject private var navigator = TVNavigator()
    @State private var reauthenticating = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea()
            if catalog.signedIn { tabs } else { SignInView() }
        }
        .environmentObject(navigator)
        .sheet(isPresented: $reauthenticating) {
            SignInView(reauthenticating: true) { player.authenticationRestored() }.tvLocalization()
        }
        .onChange(of: player.needsSignIn) { _, needed in if needed { catalog.needsSignIn = true } }
        .onChange(of: player.error) { _, error in
            guard let error else { return }
            TVDiagnostics.shared.record(player.isProgressFailure ? .sync : .media, error, detail: player.title.isEmpty ? nil : "Item: " + player.title)
        }
        .alert(l10n("Sign in again"), isPresented: $catalog.needsSignIn) {
            Button(l10n("Sign in")) { player.pause(); reauthenticating = true }
            Button(l10n("Not now"), role: .cancel) {}
        } message: {
            Text(l10n("The server no longer accepts this login. Listening saved on this TV is kept and sent after you sign in."))
        }
    }

    private var tabs: some View {
        TabView(selection: $navigator.tab) {
            HomeView()
                .tabItem { Text(l10n("Home")) }.tag(TVTab.home)
            ForEach(catalog.libraries) { library in
                LibraryView(library: library, api: catalog.api)
                    .tabItem { Text(library.name) }.tag(TVTab.library(library.id))
            }
            SearchView()
                .tabItem { Text(l10n("Search")) }.tag(TVTab.search)
            if player.session != nil || player.preparing {
                NowPlayingView()
                    .tabItem { Text(l10n("Now Playing")) }.tag(TVTab.nowPlaying)
            }
            SettingsView()
                .tabItem { Text(l10n("Settings")) }.tag(TVTab.settings)
        }
        .onPlayPauseCommand { if player.session != nil { player.toggle() } }
        .onChange(of: player.session == nil && !player.preparing) { _, ended in
            if ended && navigator.tab == .nowPlaying { navigator.tab = .home }
        }
        .task { if catalog.libraries.isEmpty { await catalog.loadCatalog() } }
        .task { await player.restoreListening() }
    }
}
