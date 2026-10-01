import SwiftUI

@main struct AudiobookshelfNativeApp: App {
    @AppStorage("previewTheme") private var theme = "system"
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(NativeDownloadAppDelegate.self) private var appDelegate
    @StateObject private var realtime: NativeRealtime
    @StateObject private var serverQueue: NativePodcastQueue
    @StateObject private var reading: ReadingStore
    @StateObject private var downloads: NativeDownloads
    @StateObject private var connection: ConnectionStore
    @StateObject private var player: ApplePlayback
    @StateObject private var migration: NativeMigrationStore

    init() {
        UITableView.appearance().backgroundColor = .clear
        let vault = KeychainCredentials()
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            try? vault.resetPreviewAccounts()
            try? FileManager.default.removeItem(at: ListeningSync.file)
            try? FileManager.default.removeItem(at: NativePodcastQueue.file)
            try? FileManager.default.removeItem(at: ReadingStore.file)
            try? FileManager.default.removeItem(at: NativeDownloads.directory)
            try? FileManager.default.removeItem(at: NativeMigrationStore.root)
            try? FileManager.default.removeItem(at: NativeMigrationAdoption.directory)
            UserDefaults.standard.removeObject(forKey: "previewTheme")
            UserDefaults.standard.removeObject(forKey: "previewHaptic")
            UserDefaults.standard.removeObject(forKey: NativeStrings.savedKey)
            try? FileManager.default.removeItem(at: NativeDiagnostics.file)
            UserDefaults.standard.removeObject(forKey: AppleNetworkPolicy.streamingKey)
            UserDefaults.standard.removeObject(forKey: AppleNetworkPolicy.downloadsKey)
            UserDefaults.standard.removeObject(forKey: "previewDownloadCellular")
            UserDefaults.standard.removeObject(forKey: "previewListLayout")
            UserDefaults.standard.removeObject(forKey: "previewLibrary")
            UserDefaults.standard.removeObject(forKey: "previewServer")
            UserDefaults.standard.removeObject(forKey: "previewUsername")
            UserDefaults.standard.removeObject(forKey: "previewPlaybackSpeed")
            UserDefaults.standard.removeObject(forKey: "previewChapterTrack")
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
        let downloads = NativeDownloads(api: api)
        _downloads = StateObject(wrappedValue: downloads)
        let playback = ApplePlayback(api: api)
        let realtimeStream = NativeRealtime(api: api, localSession: { [weak playback] in playback?.session?.id })
        _realtime = StateObject(wrappedValue: realtimeStream)
        _serverQueue = StateObject(wrappedValue: NativePodcastQueue(api: api, realtime: realtimeStream))
        let reading = ReadingStore(player: playback)
        _reading = StateObject(wrappedValue: reading)
        let adoption = NativeMigrationAdoption(downloads: downloads, reading: reading, api: api)
        _migration = StateObject(wrappedValue: NativeMigrationStore(adopter: adoption, player: playback))
        _player = StateObject(wrappedValue: playback)
        _connection = StateObject(wrappedValue: ConnectionStore(api: api, playback: playback, vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            PlaybackContainer(content: ConnectionRoot()).environmentObject(connection).environmentObject(player).environmentObject(downloads).environmentObject(reading).environmentObject(serverQueue).environmentObject(realtime)
                .accentColor(ShelfStyle.accent)
                .onAppear { Task { await connection.restore(); realtime.connect(); downloads.refresh(); reading.sync(api: connection.api); await restoreImportedData() } }
                .onChange(of: scenePhase) { phase in if phase == .active { realtime.connect(); serverQueue.retrySavingResults(); Task { await migration.sync() } } }
                .onChange(of: player.canPublishReading) { available in if available { reading.sync(api: connection.api) } }
                .onChange(of: connection.activeAccount) { _ in reading.sync(api: connection.api); Task { await migration.sync() } }
                .onChange(of: connection.signInRevision) { _ in realtime.connect() }
                .onReceive(realtime.events) { event in
                    Task {
                        guard event.isCurrent(on: connection.api) else { return }
                        switch event.change {
                        case .progress(let itemID, let episodeID, let sessionID):
                            await player.followRemoteProgress(account: event.account, itemID: itemID, episodeID: episodeID, sessionID: sessionID)
                        case .authenticated, .user:
                            await player.refreshPausedProgress(account: event.account)
                        default: break
                        }
                    }
                }
                .sheet(isPresented: $downloads.presented) { DownloadsView().environmentObject(downloads).environmentObject(player).environmentObject(reading) }
                .environmentObject(migration)
                .nativeLocalization()
                .environment(\.shelfAppearance, NativeAppearance(rawValue: theme) ?? .system)
                .preferredColorScheme((NativeAppearance(rawValue: theme) ?? .system).scheme)
        }
    }
    private func restoreImportedData() async {
        await migration.loadCommitted()
        await migration.sync()
    }

}
