import SwiftUI

@main struct AudiobookshelfTVApp: App {
    @StateObject private var store: LibraryStore
    @StateObject private var player: TVPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let api = APIClient(store: KeychainCredentials())
        _store = StateObject(wrappedValue: LibraryStore(api: api))
        _player = StateObject(wrappedValue: TVPlayer(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { player.pause() }
                }
        }
    }
}
