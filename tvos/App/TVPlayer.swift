import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor final class TVPlayer: ObservableObject {
    @Published private(set) var session: PlaybackSession?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var preparing = false
    @Published private(set) var seeking = false
    @Published var error: String?
    @Published private(set) var needsSignIn = false
    @Published var speed: Float = 1
    @Published private(set) var title = ""
    @Published private(set) var author = ""
    @Published private(set) var itemID: String?
    private let api: APIClient
    private let player = AVPlayer()
    private var trackIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatus: NSKeyValueObservation?
    private var controlStatus: NSKeyValueObservation?
    private var syncTask: Task<Void, Never>?
    private var pendingListening: Double = 0
    private var lastTick = Date()
    private var lastSync = Date()
    private var generation = UUID()
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(api: APIClient) {
        self.api = api
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
        controlStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let active = player.timeControlStatus == .playing
            Task { @MainActor in self?.playing = active }
        }
        let commands = MPRemoteCommandCenter.shared()
        commandTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }))
        commandTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }))
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.preferredIntervals = [30]
        commandTargets.append((commands.skipForwardCommand, commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.skip(30) }; return .success
        }))
        commandTargets.append((commands.skipBackwardCommand, commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.skip(-30) }; return .success
        }))
    }

    func start(item: LibraryItem, episode: Episode? = nil) async {
        guard !preparing, !seeking else { return }
        preparing = true
        error = nil
        defer { preparing = false }
        do {
            try await stop()
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .spokenAudio)
            try audio.setActive(true)
            let deviceID: String
            if let stored = UserDefaults.standard.string(forKey: "tvDeviceID") { deviceID = stored }
            else {
                deviceID = UUID().uuidString
                UserDefaults.standard.set(deviceID, forKey: "tvDeviceID")
            }
            let result = try await api.play(itemID: item.id, episodeID: episode?.id, deviceID: deviceID)
            session = result
            generation = UUID()
            itemID = item.id
            title = episode?.title ?? item.title
            author = item.author
            pendingListening = 0
            lastTick = Date(); lastSync = Date()
            try await seek(to: result.currentTime, autoplay: true)
        } catch { failed(error) }
    }

    func toggle() { if playing { pause() } else { resume() } }
    func resume() {
        guard session != nil, !seeking else { return }
        if let session, currentTime >= session.duration - 0.1 {
            Task { do { try await seek(to: 0, autoplay: true) } catch { failed(error) } }
        } else {
            lastTick = Date()
            player.playImmediately(atRate: speed)
            updateNowPlaying()
        }
    }
    func pause() {
        tick(player.currentTime())
        player.pause()
        playing = false
        updateNowPlaying()
        sync()
    }
    func changeSpeed() {
        if playing { player.rate = speed }
        updateNowPlaying()
    }
    func skip(_ amount: Double) async {
        do { try await seek(to: currentTime + amount, autoplay: playing) }
        catch { failed(error) }
    }
    func seek(to time: Double, autoplay: Bool) async throws {
        guard !seeking, let session, let position = session.position(at: time) else { return }
        tick(player.currentTime())
        let requestGeneration = generation
        seeking = true
        defer { seeking = false }
        player.pause()
        playing = false
        if player.currentItem == nil || trackIndex != position.trackIndex {
            try await loadTrack(position.trackIndex)
        }
        guard requestGeneration == generation else { return }
        let finished = await player.seek(to: CMTime(seconds: position.localTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard finished, requestGeneration == generation else { return }
        currentTime = min(max(time.isFinite ? time : 0, 0), session.duration)
        lastTick = Date()
        if autoplay { player.playImmediately(atRate: speed) }
        updateNowPlaying()
        sync()
    }

    private func loadTrack(_ index: Int) async throws {
        guard let session else { return }
        let requestGeneration = generation
        let token = try await api.validToken()
        guard requestGeneration == generation, self.session?.id == session.id else { throw CancellationError() }
        let url = try api.mediaURL(session.audioTracks[index].contentUrl)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
        let item = AVPlayerItem(asset: asset)
        trackIndex = index
        itemStatus = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.player.currentItem === item else { return }
                await self?.trackEnded()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playbackFailed() }
        }
        itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { Task { @MainActor in self?.playbackFailed() } }
        }
        player.replaceCurrentItem(with: item)
    }

    private func playbackFailed() {
        pause()
        error = "Audio could not be played. Check the server connection, then reopen this item to retry."
    }
    private func trackEnded() async {
        guard let session else { return }
        tick(player.currentTime())
        if trackIndex + 1 < session.audioTracks.count {
            do { try await seek(to: session.audioTracks[trackIndex + 1].startOffset, autoplay: true) }
            catch { failed(error) }
        } else {
            currentTime = session.duration
            player.pause(); playing = false
            sync()
            updateNowPlaying()
        }
    }

    private func tick(_ observedTime: CMTime) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        guard let session, !seeking else { return }
        let time = player.currentTime()
        if player.timeControlStatus == .playing { pendingListening += min(max(elapsed, 0), 2) }
        if time.seconds.isFinite { currentTime = min(session.duration, session.audioTracks[trackIndex].startOffset + max(time.seconds, 0)) }
        if now.timeIntervalSince(lastSync) >= 15 { sync() }
        updateNowPlaying()
    }

    func sync() {
        guard syncTask == nil, let session else { return }
        let sentListening = pendingListening
        let report = ProgressReport(currentTime: currentTime, timeListened: sentListening, duration: session.duration)
        lastSync = Date()
        syncTask = Task { @MainActor in
            defer { syncTask = nil }
            do {
                try await api.report(sessionID: session.id, report: report)
                pendingListening = max(0, pendingListening - sentListening)
                lastSync = Date()
            } catch { failed(error, prefix: "Playback progress could not be saved: ") }
        }
    }

    func authenticationRestored() {
        needsSignIn = false
        error = nil
        sync()
    }

    private func failed(_ failure: Error, prefix: String = "") {
        if failure as? APIError == .signInRequired { needsSignIn = true }
        error = prefix + failure.localizedDescription
    }

    func stop() async throws {
        tick(player.currentTime())
        player.pause()
        playing = false
        if let syncTask { await syncTask.value }
        if let session {
            let report = ProgressReport(currentTime: currentTime, timeListened: pendingListening, duration: session.duration)
            // Do not discard the session or its unsent progress if closing it fails.
            try await api.report(sessionID: session.id, report: report, close: true)
        }
        generation = UUID()
        player.replaceCurrentItem(with: nil)
        session = nil; itemID = nil; currentTime = 0; pendingListening = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlaying() {
        guard let session else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: session.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0
        ]
    }
}
