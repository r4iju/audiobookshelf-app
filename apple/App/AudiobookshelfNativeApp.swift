import SwiftUI

@main struct AudiobookshelfNativeApp: App {
    @StateObject private var connection: ConnectionStore
    @StateObject private var player: ApplePlayback

    init() {
        let vault = KeychainCredentials()
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            try? vault.clear()
            try? FileManager.default.removeItem(at: ListeningSync.file)
            UserDefaults.standard.removeObject(forKey: "previewLibrary")
            UserDefaults.standard.removeObject(forKey: "previewServer")
            UserDefaults.standard.removeObject(forKey: "previewUsername")
        }
        #endif
        let api = APIClient(store: vault)
        let playback = ApplePlayback(api: api)
        _player = StateObject(wrappedValue: playback)
        _connection = StateObject(wrappedValue: ConnectionStore(api: api, playback: playback))
    }

    var body: some Scene {
        WindowGroup {
            PlaybackContainer(content: ConnectionRoot()).environmentObject(connection).environmentObject(player)
                .accentColor(ShelfStyle.accent)
                .onAppear { Task { await connection.restore() } }
        }
    }
}
