import SwiftUI

@main struct AudiobookshelfNativeApp: App {
    @StateObject private var connection: ConnectionStore
    @StateObject private var player: ApplePlayback

    init() {
        let vault = KeychainCredentials()
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            try? vault.resetPreviewAccounts()
            try? FileManager.default.removeItem(at: ListeningSync.file)
            UserDefaults.standard.removeObject(forKey: "previewLibrary")
            UserDefaults.standard.removeObject(forKey: "previewServer")
            UserDefaults.standard.removeObject(forKey: "previewUsername")
            UserDefaults.standard.removeObject(forKey: "previewPlaybackSpeed")
            UserDefaults.standard.removeObject(forKey: "previewSleepFade")
            UserDefaults.standard.removeObject(forKey: "previewSkipForward")
            UserDefaults.standard.removeObject(forKey: "previewSkipBackward")
            UserDefaults.standard.removeObject(forKey: "previewResumeRewind")
            UserDefaults.standard.removeObject(forKey: "previewMediaSeeking")
        }
        if CommandLine.arguments.contains("--seed-legacy-preview-account") {
            try? vault.seedLegacyPreviewAccount()
            UserDefaults.standard.set("books", forKey: "previewLibrary")
        }
        #endif
        let api = APIClient(store: vault)
        let playback = ApplePlayback(api: api)
        _player = StateObject(wrappedValue: playback)
        _connection = StateObject(wrappedValue: ConnectionStore(api: api, playback: playback, vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            PlaybackContainer(content: ConnectionRoot()).environmentObject(connection).environmentObject(player)
                .accentColor(ShelfStyle.accent)
                .onAppear { Task { await connection.restore() } }
        }
    }
}
