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
            for key in [CatalogStore.lastServerKey, CatalogStore.lastUsernameKey, "NativeListeningJournal", ListeningStorage.publicationsKey, ListeningStorage.resetsKey, NativeStrings.savedKey] { UserDefaults.standard.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: ListeningSync.file)
            // Uncertain writes of an earlier journey would hold back this one's progress.
            try? FileManager.default.removeItem(at: ListeningSync.publicationsFile)
            try? FileManager.default.removeItem(at: TVDiagnostics.file)
        }
        #endif
        let api = APIClient(store: KeychainCredentials())
        _catalog = StateObject(wrappedValue: CatalogStore(api: api))
        _player = StateObject(wrappedValue: TVPlayer(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tvLocalization()
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
