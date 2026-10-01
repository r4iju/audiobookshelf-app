import SwiftUI

@main struct AudiobookshelfNativeApp: App {
    @UIApplicationDelegateAdaptor(NativeDownloadAppDelegate.self) private var appDelegate
    @StateObject private var reading: ReadingStore
    @StateObject private var downloads: NativeDownloads
    @StateObject private var connection: ConnectionStore
    @StateObject private var player: ApplePlayback

    init() {
        let vault = KeychainCredentials()
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            try? vault.resetPreviewAccounts()
            try? FileManager.default.removeItem(at: ListeningSync.file)
            try? FileManager.default.removeItem(at: ReadingStore.file)
            try? FileManager.default.removeItem(at: NativeDownloads.directory)
            UserDefaults.standard.removeObject(forKey: "previewListLayout")
            UserDefaults.standard.removeObject(forKey: "previewLibrary")
            UserDefaults.standard.removeObject(forKey: "previewServer")
            UserDefaults.standard.removeObject(forKey: "previewUsername")
            UserDefaults.standard.removeObject(forKey: "previewPlaybackSpeed")
            UserDefaults.standard.removeObject(forKey: "previewSleepFade")
            UserDefaults.standard.removeObject(forKey: "previewSkipForward")
            UserDefaults.standard.removeObject(forKey: "previewSkipBackward")
            UserDefaults.standard.removeObject(forKey: "previewResumeRewind")
            UserDefaults.standard.removeObject(forKey: "previewMediaSeeking")
            UserDefaults.standard.removeObject(forKey: "previewEpisodeSort")
            UserDefaults.standard.removeObject(forKey: "previewEpisodeDescending")
            UserDefaults.standard.removeObject(forKey: "previewPDFContinuous")
            UserDefaults.standard.removeObject(forKey: "previewEPUBPreferences")
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("previewServerPodcastRequests.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if CommandLine.arguments.contains("--unreadable-preview-reading") {
            try? FileManager.default.createDirectory(at: ReadingStore.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("damaged reading document".utf8).write(to: ReadingStore.file, options: .atomic)
        }
        if CommandLine.arguments.contains("--seed-legacy-preview-account") {
            try? vault.seedLegacyPreviewAccount()
            UserDefaults.standard.set("books", forKey: "previewLibrary")
        }
        #endif
        let api = APIClient(store: vault)
        _downloads = StateObject(wrappedValue: NativeDownloads(api: api))
        let playback = ApplePlayback(api: api)
        _reading = StateObject(wrappedValue: ReadingStore(player: playback))
        _player = StateObject(wrappedValue: playback)
        _connection = StateObject(wrappedValue: ConnectionStore(api: api, playback: playback, vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            PlaybackContainer(content: ConnectionRoot()).environmentObject(connection).environmentObject(player).environmentObject(downloads).environmentObject(reading)
                .accentColor(ShelfStyle.accent)
                .onAppear { Task { await connection.restore(); downloads.refresh(); reading.sync(api: connection.api) } }
                .onChange(of: player.canPublishReading) { available in if available { reading.sync(api: connection.api) } }
                .onChange(of: connection.activeAccount) { _ in reading.sync(api: connection.api) }
                .sheet(isPresented: $downloads.presented) { DownloadsView().environmentObject(downloads).environmentObject(player).environmentObject(reading) }
        }
    }
}
