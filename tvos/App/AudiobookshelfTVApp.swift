import SwiftUI

@main struct AudiobookshelfTVApp: App {
    @StateObject private var catalog: CatalogStore
    @StateObject private var player: TVPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Debug-only isolation for remote UI journeys; signed device builds use Release.
        if ProcessInfo.processInfo.arguments.contains("--reset-tv-state") {
            try? KeychainCredentials().clear()
            for key in [CatalogStore.lastServerKey, CatalogStore.lastUsernameKey, "NativeListeningJournal"] { UserDefaults.standard.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: ListeningSync.file)
        }
        #endif
        let api = APIClient(store: KeychainCredentials())
        _catalog = StateObject(wrappedValue: CatalogStore(api: api))
        _player = StateObject(wrappedValue: TVPlayer(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(catalog)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onChange(of: scenePhase) { previous, phase in
                    // The TV app has no background audio: leaving it pauses and saves. The
                    // inactive phase (Control Center, screen saver) keeps listening.
                    if phase == .background { player.pause() }
                    if phase == .active, previous == .background, catalog.signedIn {
                        Task { await player.restoreListening() }
                    }
                }
        }
    }
}
