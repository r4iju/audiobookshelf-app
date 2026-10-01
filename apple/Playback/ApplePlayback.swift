import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor final class ApplePlayback: ObservableObject {
    @Published private(set) var session: PlaybackSession?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var wantsPlayback = false
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
    @Published private(set) var trackIndex = 0
    private struct SeekRequest {
        let time: Double
        let generation: UUID
    }
    private var pendingSeek: SeekRequest?
    private var seekLoop: Task<Void, Error>?
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

    private static var deviceKey: String {
        #if os(tvOS)
        return "tvDeviceID"
        #else
        return "nativeDeviceID"
        #endif
    }

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
            wantsPlayback = true
            itemID = item.id
            title = episode?.title ?? item.title
            author = item.author
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .spokenAudio)
            try audio.setActive(true)
            let deviceID: String
            if let stored = UserDefaults.standard.string(forKey: Self.deviceKey) { deviceID = stored }
            else {
                deviceID = UUID().uuidString
                UserDefaults.standard.set(deviceID, forKey: Self.deviceKey)
            }
            let requestGeneration = generation
            let result = try await api.play(itemID: item.id, episodeID: episode?.id, deviceID: deviceID)
            guard requestGeneration == generation else {
                try await api.report(sessionID: result.id, report: ProgressReport(currentTime: result.currentTime, timeListened: 0, duration: result.duration), close: true)
                return
            }
            session = result
            generation = UUID()
            itemID = item.id
            title = episode?.title ?? item.title
            author = item.author
            pendingListening = 0
            lastTick = Date(); lastSync = Date()
            try await seek(to: result.currentTime, autoplay: wantsPlayback)
        } catch { wantsPlayback = false; failed(error) }
    }

    func toggle() { if wantsPlayback { pause() } else { resume() } }
    func resume() {
        wantsPlayback = true
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
        wantsPlayback = false
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
        do { try await seek(to: currentTime + amount, autoplay: wantsPlayback) }
        catch { failed(error) }
    }
    func seek(to time: Double, autoplay: Bool) async throws {
        guard let session, session.position(at: time) != nil else { return }
        wantsPlayback = autoplay
        pendingSeek = SeekRequest(time: min(max(time.isFinite ? time : 0, 0), session.duration), generation: generation)
        if let seekLoop { return try await seekLoop.value }
        tick(player.currentTime())
        let loop = Task { @MainActor in
            seeking = true
            defer { seeking = false }
            player.pause()
            playing = false
            while let request = pendingSeek {
                pendingSeek = nil
                try Task.checkCancellation()
                guard request.generation == generation, let session = self.session,
                      let position = session.position(at: request.time) else { throw CancellationError() }
                if player.currentItem == nil || trackIndex != position.trackIndex {
                    try await loadTrack(position.trackIndex)
                }
                guard request.generation == generation else { throw CancellationError() }
                if pendingSeek != nil { continue }
                let finished = await player.seek(to: CMTime(seconds: position.localTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard request.generation == generation else { throw CancellationError() }
                if pendingSeek != nil { continue }
                guard finished else { throw PlaybackFailure.seekFailed }
                currentTime = request.time
                lastTick = Date()
            }
            if wantsPlayback { player.playImmediately(atRate: speed) }
            updateNowPlaying()
            sync()
        }
        seekLoop = loop
        defer { seekLoop = nil }
        try await loop.value
    }

    private enum PlaybackFailure: LocalizedError {
        case seekFailed
        var errorDescription: String? { "Audio could not be prepared at this position. Check the server connection and try again." }
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
            Task { @MainActor in
                guard self?.player.currentItem === item else { return }
                self?.playbackFailed()
            }
        }
        itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                Task { @MainActor in
                    guard self?.player.currentItem === item else { return }
                    self?.playbackFailed()
                }
            }
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
            wantsPlayback = false
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
        if failure is CancellationError { return }
        if failure as? APIError == .signInRequired { needsSignIn = true }
        error = prefix + failure.localizedDescription
    }

    func stop() async throws {
        tick(player.currentTime())
        generation = UUID()
        pendingSeek = nil
        wantsPlayback = false
        seekLoop?.cancel()
        player.currentItem?.cancelPendingSeeks()
        if let seekLoop { _ = try? await seekLoop.value }
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
