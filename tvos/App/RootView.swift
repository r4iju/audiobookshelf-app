import SwiftUI

enum TVTab: Hashable {
    case home, library, search, nowPlaying, settings
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
    @State private var signInPrompt = false

    var body: some View {
        ZStack {
            TVSceneBackground()
            if catalog.signedIn { tabs } else { SignInView() }
        }
        .environmentObject(navigator)
        // Full screen like the first sign-in: a sheet is too narrow for the form. Back closes it with the book paused.
        .fullScreenCover(isPresented: $reauthenticating) {
            SignInView(reauthenticating: true) { player.authenticationRestored() }.tvLocalization()
                .background(TVSceneBackground())
        }
        .onChange(of: player.needsSignIn) { _, needed in if needed { catalog.needsSignIn = true } }
        .onChange(of: player.error) { _, error in
            guard let error else { return }
            TVDiagnostics.shared.record(player.isProgressFailure ? .sync : .media, error, detail: player.title.isEmpty ? nil : "Item: " + player.title)
        }
        // SwiftUI owns alert dismissal locally; its binding must not publish a store
        // change while the native presentation hierarchy is updating.
        .onReceive(catalog.$needsSignIn) { needed in
            if !reauthenticating { signInPrompt = needed }
        }
        .alert(l10n("Sign in again"), isPresented: $signInPrompt) {
            Button(l10n("Sign in")) { catalog.needsSignIn = false; player.pause(); reauthenticating = true }
            Button(l10n("Not now"), role: .cancel) { catalog.needsSignIn = false }
        } message: {
            Text(l10n("The server no longer accepts this login. Listening saved on this TV is kept and sent after you sign in."))
        }
    }

    private var tabs: some View {
        TabView(selection: $navigator.tab) {
            HomeView()
                .tabItem { Label(l10n("Listen Now"), systemImage: "play.circle") }.tag(TVTab.home)
            LibraryDestination()
                .tabItem { Label(l10n("Library"), systemImage: "books.vertical") }.tag(TVTab.library)
            SearchView()
                .tabItem { Label(l10n("Search"), systemImage: "magnifyingglass") }.tag(TVTab.search)
            if player.session != nil || player.preparing {
                NowPlayingView()
                    .tabItem { Label(l10n("Now Playing"), systemImage: "waveform") }.tag(TVTab.nowPlaying)
            }
            SettingsView()
                .tabItem { Label(l10n("Settings"), systemImage: "gearshape") }.tag(TVTab.settings)
        }
        .onPlayPauseCommand { if player.session != nil { player.toggle() } }
        .onChange(of: player.session == nil && !player.preparing) { _, ended in
            if ended && navigator.tab == .nowPlaying { navigator.tab = .home }
        }
        .task { if catalog.libraries.isEmpty { await catalog.loadCatalog() } }
        .task { await player.restoreListening() }
    }
}
