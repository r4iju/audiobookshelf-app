import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor final class ApplePlayback: ObservableObject {
    @Published private(set) var session: PlaybackSession?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var wantsPlayback = false
    @Published private(set) var preparing = false
    @Published private(set) var seeking = false
    @Published var error: String? { didSet { failureOrigin = .playback } }
    private enum FailureOrigin { case playback, progress }
    private var failureOrigin = FailureOrigin.playback
    var isProgressFailure: Bool { failureOrigin == .progress }
    @Published private(set) var needsSignIn = false
    @Published var speed: Float = 1
    private static var defaultChapterTrack: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    @Published var chapterTrack = UserDefaults.standard.object(forKey: "previewChapterTrack") as? Bool ?? ApplePlayback.defaultChapterTrack {
        didSet {
            UserDefaults.standard.set(chapterTrack, forKey: "previewChapterTrack")
            updateNowPlaying()
        }
    }
    @Published var forwardInterval = UserDefaults.standard.object(forKey: "previewSkipForward") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(forwardInterval, forKey: "previewSkipForward"); updateSkipCommands() }
    }
    @Published var backwardInterval = UserDefaults.standard.object(forKey: "previewSkipBackward") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(backwardInterval, forKey: "previewSkipBackward"); updateSkipCommands() }
    }
    @Published private(set) var title = ""
    @Published private(set) var author = ""
    @Published private(set) var itemID: String?
    @Published private(set) var episodeID: String?
    @Published private(set) var bookmarkSupported = false
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var bookmarkBusy = false
    @Published private(set) var bookmarkError: String?
    @Published private(set) var sleepRemaining: Double?
    @Published private(set) var sleepChapterEnd: Double?
    var audioVolume: Float { player.volume }
    private var sleepTask: Task<Void, Never>?
    private var sleepBoundary: Any?
    private var sleepID = UUID()
    private var sleepLength: Double?
    private var sleepTick = Date()
    private var fadeStartPosition: Double?
    private var pausedAt: Date?
    private var interruptedGeneration: UUID?
    private var playbackIntent = UUID()
    var playbackIntentID: UUID { playbackIntent }
    private var audioObservers: [NSObjectProtocol] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    @Published var rewindAfterPause = UserDefaults.standard.object(forKey: "previewResumeRewind") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rewindAfterPause, forKey: "previewResumeRewind") }
    }
    @Published var allowMediaSeeking = UserDefaults.standard.bool(forKey: "previewMediaSeeking") {
        didSet {
            UserDefaults.standard.set(allowMediaSeeking, forKey: "previewMediaSeeking")
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = allowMediaSeeking
        }
    }
    @Published var fadeSleepTimer = UserDefaults.standard.object(forKey: "previewSleepFade") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(fadeSleepTimer, forKey: "previewSleepFade")
            if !fadeSleepTimer { player.volume = 1; fadeStartPosition = nil }
        }
    }
    var currentChapter: Chapter? {
        session?.chapters?.last { $0.start <= currentTime && currentTime < $0.end }
    }
    @Published private(set) var offlineID: String?
    private var offlineFiles: [URL]?
    #if os(iOS)
    private var streamCellularConsent: Bool?
    private var networkEpoch = UUID()
    #endif
    private let api: APIClient
    let listening: ListeningSync
    private var readingPublication: Task<Void, Error>?
    var canPublishReading: Bool { session == nil && !preparing && !closing && progressReset == nil }
    @Published private var progressReset: Task<CurrentUser, Error>?
    private var resetCleanups: [String: @MainActor (ProgressResetIntent) throws -> Void] = [:]
    private var listeningID: String?
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
    private var lastTick = Date()
    private var measuredPlayback = false
    private var measuredSpeed: Float = 1
    private var lastSync = Date()
    private var generation = UUID()
    private var preparationID = UUID()
    @Published private var closing = false
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    private static var deviceKey: String {
        #if os(tvOS)
        return "tvDeviceID"
        #else
        return "nativeDeviceID"
        #endif
    }

    init(api: APIClient, progressResets: URL? = nil) {
        self.api = api
        let savedSpeed = UserDefaults.standard.float(forKey: "previewPlaybackSpeed")
        speed = savedSpeed >= 0.5 && savedSpeed <= 10 ? savedSpeed : 1
        listening = ListeningSync(api: api, resets: progressResets)
        #if os(iOS)
        audioObservers.append(NotificationCenter.default.addObserver(forName: AppleNetworkPolicy.changed, object: nil, queue: .main) { [weak self] note in
            guard note.object as? String == AppleNetworkPolicy.streamingKey else { return }
            Task { @MainActor in
                guard let self, self.offlineFiles == nil else { return }
                self.networkEpoch = UUID()
                self.pause()
                self.streamCellularConsent = nil
                self.player.replaceCurrentItem(with: nil)
            }
        })
        #endif
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
        controlStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.playing = self.player.timeControlStatus == .playing
            }
        }
        let commands = MPRemoteCommandCenter.shared()
        commandTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }))
        commandTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }))
        commandTargets.append((commands.togglePlayPauseCommand, commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success
        }))
        commands.changePlaybackPositionCommand.isEnabled = allowMediaSeeking
        commandTargets.append((commands.changePlaybackPositionCommand, commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in
                guard let self, self.allowMediaSeeking else { return }
                do { try await self.seekFromMediaControls(to: position) } catch { self.failed(error) }
            }
            return .success
        }))
        observeAudioSession()
        updateSkipCommands()
        commandTargets.append((commands.skipForwardCommand, commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in guard let self else { return }; await self.skip(Double(self.forwardInterval)) }; return .success
        }))
        commandTargets.append((commands.skipBackwardCommand, commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in guard let self else { return }; await self.skip(-Double(self.backwardInterval)) }; return .success
        }))
    }

    func start(item: LibraryItem, episode: Episode? = nil) async {
        guard !preparing, !seeking, !closing else { return }
        #if os(iOS)
        streamCellularConsent = nil
        #endif
        let preparation = UUID()
        preparationID = preparation
        preparing = true
        wantsPlayback = true
        error = nil
        defer { if preparationID == preparation { preparing = false } }
        do {
            if let readingPublication { _ = try? await readingPublication.value }
            if let progressReset { _ = try? await progressReset.value }
            guard preparationID == preparation else { return }
            try await finishProgressReset(account: try await api.currentAccount(), itemID: item.id, episodeID: episode?.id)
            guard preparationID == preparation else { return }
            try await closeCurrentSession()
            let requestGeneration = generation
            try await listening.flush()
            guard requestGeneration == generation else { return }
            itemID = item.id
            episodeID = episode?.id
            bookmarkSupported = item.mediaType == "book"
            title = episode?.title ?? item.title
            author = item.author
            try await Self.activateAudioSession()
            guard requestGeneration == generation else { return }
            let deviceID: String
            if let stored = UserDefaults.standard.string(forKey: Self.deviceKey) { deviceID = stored }
            else {
                deviceID = UUID().uuidString
                UserDefaults.standard.set(deviceID, forKey: Self.deviceKey)
            }
            let result = try await api.play(itemID: item.id, episodeID: episode?.id, deviceID: deviceID)
            guard requestGeneration == generation else {
                try await api.closeStream(sessionID: result.id)
                return
            }
            session = result
            pausedAt = nil
            interruptedGeneration = nil
            nowPlayingArtwork = nil
            currentTime = result.currentTime
            generation = UUID()
            itemID = item.id
            episodeID = episode?.id
            title = episode?.title ?? item.title
            author = item.author
            listeningID = try await listening.begin(media: ListeningMedia(item: item, episode: episode, session: result), deviceID: deviceID)
            lastTick = Date(); lastSync = Date()
            try await seek(to: result.currentTime, autoplay: wantsPlayback)
            Task { @MainActor [weak self] in
                guard let self, let data = try? await self.api.coverData(itemID: item.id),
                      self.session?.id == result.id, let image = UIImage(data: data) else { return }
                self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlaying()
            }
        } catch {
            guard preparationID == preparation else { return }
            wantsPlayback = false
            failed(error)
        }
    }

    func hasFinishedOffline(_ audio: OfflineAudio, serverFinished: Bool) throws -> Bool {
        try listening.hasFinished(audio, serverFinished: serverFinished)
    }

    func resumeOffline(_ audio: OfflineAudio) async throws {
        guard try await api.currentAccount() == audio.account else { throw APIError.signInRequired }
        guard offlineID == audio.id, session != nil else { await startOffline(audio); return }
        let position = try listening.position(for: audio)
        if abs(position - currentTime) > 0.1 {
            pausedAt = nil
            try await seek(to: position, autoplay: true)
        } else { resume() }
    }

    func startOffline(_ audio: OfflineAudio) async {
        guard !preparing, !seeking, !closing else { return }
        let preparation = UUID()
        preparationID = preparation; preparing = true; wantsPlayback = true; error = nil
        playbackIntent = UUID()
        let initialIntent = playbackIntent
        defer { if preparationID == preparation { preparing = false } }
        do {
            if let readingPublication { _ = try? await readingPublication.value }
            if let progressReset { _ = try? await progressReset.value }
            guard preparationID == preparation else { return }
            guard try await api.currentAccount() == audio.account else { throw APIError.signInRequired }
            try await finishProgressReset(account: audio.account, itemID: audio.media.libraryItemID, episodeID: audio.media.episodeID)
            guard preparationID == preparation else { return }
            try await suspendForConnectionChange(preservingIntent: initialIntent)
            preparationID = preparation; preparing = true
            let request = generation
            try await Self.activateAudioSession()
            guard request == generation else { return }
            let position = min(max(try listening.position(for: audio), 0), audio.media.duration)
            let tracks = zip(audio.tracks, audio.files).map { track, file in
                AudioTrack(contentUrl: file.absoluteString, metadata: nil, startOffset: track.startOffset, duration: track.duration)
            }
            session = PlaybackSession(id: "offline-" + UUID().uuidString, currentTime: position, duration: audio.media.duration, audioTracks: tracks, chapters: audio.chapters, displayTitle: audio.media.title, displayAuthor: audio.media.author)
            offlineID = audio.id; offlineFiles = audio.files
            itemID = audio.media.libraryItemID; episodeID = audio.media.episodeID
            title = audio.media.title; author = audio.media.author; currentTime = position
            bookmarkSupported = false; nowPlayingArtwork = nil
            let deviceID = UserDefaults.standard.string(forKey: Self.deviceKey) ?? UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: Self.deviceKey)
            listeningID = try listening.beginOffline(audio, position: position, deviceID: deviceID)
            lastTick = Date(); lastSync = Date()
            try await seek(to: position, autoplay: wantsPlayback)
        } catch {
            guard preparationID == preparation else { return }
            wantsPlayback = false; failed(error)
        }
    }

    func toggle() { if wantsPlayback { pause() } else { resume() } }
    func resume() {
        playbackIntent = UUID()
        let pausedDuration = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        let rewind: Double = !rewindAfterPause || pausedDuration < 10 ? 0 : pausedDuration < 60 ? 3 : pausedDuration < 300 ? 10 : pausedDuration < 1800 ? 20 : 30
        pausedAt = nil
        wantsPlayback = true
        guard let session, !seeking, !closing else { return }
        if player.currentItem == nil || rewind > 0 || currentTime >= session.duration - 0.1 || session.position(at: currentTime)?.trackIndex != trackIndex {
            let target = currentTime >= session.duration - 0.1 ? 0 : max(0, currentTime - rewind)
            Task { do { try await seek(to: target, autoplay: wantsPlayback) } catch { failed(error) } }
        } else {
            lastTick = Date()
            player.playImmediately(atRate: speed)
            updateNowPlaying()
        }
    }
    func pause() {
        playbackIntent = UUID()
        if wantsPlayback { pausedAt = Date() }
        interruptedGeneration = nil
        wantsPlayback = false
        tick(player.currentTime())
        player.pause()
        playing = false
        updateNowPlaying()
        sync()
    }
    func changeSpeed() {
        tick(player.currentTime())
        speed = speed.isFinite ? min(max(speed, 0.5), 10) : 1
        UserDefaults.standard.set(speed, forKey: "previewPlaybackSpeed")
        measuredSpeed = speed
        if playing { player.rate = speed }
        updateNowPlaying()
    }
    private func updateSkipCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardInterval)]
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardInterval)]
    }
    func seekFromMediaControls(to position: Double) async throws {
        guard position.isFinite else { return }
        let target: Double
        if let window = mediaChapterWindow {
            target = window.start + min(max(position, 0), window.end - window.start)
        } else { target = position }
        try await seek(to: target, autoplay: wantsPlayback)
    }
    func skip(_ amount: Double) async {
        do { try await seek(to: currentTime + amount, autoplay: wantsPlayback) }
        catch { failed(error) }
    }
    func seek(to time: Double, autoplay: Bool) async throws {
        guard !closing, let session, session.position(at: time) != nil else { return }
        playbackIntent = UUID()
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
                guard !closing, request.generation == generation, let session = self.session,
                      let position = session.position(at: request.time) else { throw CancellationError() }
                if player.currentItem == nil || trackIndex != position.trackIndex {
                    try await loadTrack(position.trackIndex)
                }
                guard !closing, request.generation == generation else { throw CancellationError() }
                if pendingSeek != nil { continue }
                let finished = await player.seek(to: CMTime(seconds: position.localTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard !closing, request.generation == generation else { throw CancellationError() }
                if pendingSeek != nil { continue }
                guard finished else { throw PlaybackFailure.seekFailed }
                if let listeningID { try listening.record(id: listeningID, position: request.time, listened: 0) }
                currentTime = request.time
                if let end = sleepChapterEnd, currentTime >= end { endSleepTimer() }
                lastTick = Date()
                measuredPlayback = false
                measuredSpeed = speed
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
        #if os(iOS)
        let requestNetworkEpoch = networkEpoch
        #endif
        let asset: AVURLAsset
        if let offlineFiles {
            guard offlineFiles.indices.contains(index), offlineFiles[index].isFileURL else { throw APIError.noAudio }
            asset = AVURLAsset(url: offlineFiles[index])
        } else {
            let token = try await api.validToken()
            guard requestGeneration == generation, self.session?.id == session.id else { throw CancellationError() }
            let url = try api.mediaURL(session.audioTracks[index].contentUrl)
            var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
            #if os(iOS)
            if streamCellularConsent == nil {
                let policy = AppleNetworkPolicy.read(AppleNetworkPolicy.streamingKey)
                let allowed = await AppleNetworkPolicy.request(AppleNetworkPolicy.streamingKey, title: NativeStrings.current("this listening session"))
                guard requestGeneration == generation, self.session?.id == session.id else { throw CancellationError() }
                guard policy == AppleNetworkPolicy.read(AppleNetworkPolicy.streamingKey) else { throw CancellationError() }
                streamCellularConsent = allowed
            }
            options[AVURLAssetAllowsCellularAccessKey] = streamCellularConsent == true
            #endif
            asset = AVURLAsset(url: url, options: options)
        }
        #if os(iOS)
        guard requestNetworkEpoch == networkEpoch else { throw CancellationError() }
        #endif
        let item = AVPlayerItem(asset: asset)
        trackIndex = index
        itemStatus = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.player.currentItem === item, self?.generation == requestGeneration else { return }
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
        installSleepBoundary()
    }

    private func playbackFailed() {
        pause()
        error = "Audio could not be played. Check the server connection, then reopen this item to retry."
    }
    private func trackEnded() async {
        guard let session, !closing, !seeking else { return }
        tick(player.currentTime())
        if let end = sleepChapterEnd, currentTime >= end - 0.05 { endSleepTimer(); return }
        if trackIndex + 1 < session.audioTracks.count {
            guard wantsPlayback else { return }
            do { try await seek(to: session.audioTracks[trackIndex + 1].startOffset, autoplay: wantsPlayback) }
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
        guard let session, !seeking, !closing, player.currentItem != nil else { return }
        let time = player.currentTime()
        if time.seconds.isFinite {
            let position = min(session.duration, session.audioTracks[trackIndex].startOffset + max(time.seconds, 0))
            let active = player.timeControlStatus == .playing
            let delta = active || measuredPlayback ? min(max(elapsed, 0), max((position - currentTime) / Double(measuredSpeed), 0)) : 0
            measuredPlayback = active
            do {
                if let listeningID, abs(position - currentTime) > 0.001 || delta > 0 {
                    try listening.record(id: listeningID, position: position, listened: delta)
                }
                currentTime = position
            } catch {
                player.pause()
                playing = false
                wantsPlayback = false
                failed(error, prefix: "Listening could not be saved on this device: ")
            }
        }
        if now.timeIntervalSince(lastSync) >= 15 { sync() }
        updateNowPlaying()
    }

    func sync() {
        guard syncTask == nil, !closing, session != nil else { return }
        lastSync = Date()
        syncTask = Task { @MainActor in
            defer { syncTask = nil }
            do {
                try await listening.flush()
                lastSync = Date()
                clearProgressFailure()
            } catch { failed(error, prefix: "Playback progress could not be saved: ", origin: .progress) }
        }
    }

    func authenticationRestored() {
        needsSignIn = false
        error = nil
        sync()
    }

    /// Moves a paused player to progress another session saved for the open media, as the baseline
    /// player does for `user_media_progress_updated`. Returns whether the player moved.
    @discardableResult
    func followRemoteProgress(account: AccountIdentity, itemID: String, episodeID: String?, sessionID: String?) async -> Bool {
        guard itemID == self.itemID, episodeID == self.episodeID,
              sessionID == nil || (sessionID != session?.id && sessionID != listeningID) else { return false }
        return await followPausedProgress(account: account)
    }

    /// Progress events can be missed while disconnected; call after reconnecting to refresh paused media.
    @discardableResult
    func refreshPausedProgress(account: AccountIdentity) async -> Bool {
        await followPausedProgress(account: account)
    }

    // Never publishes first: a 2.30 local session sync replaces server progress that is not strictly
    // newer, which could erase the other device's movement. Unsent or newer own listening is left to
    // the regular sync, and any local change while the server answers keeps the local position.
    private func followPausedProgress(account: AccountIdentity) async -> Bool {
        guard let session, let itemID else { return false }
        let episodeID = self.episodeID
        let authorization = api.authorizationRevision
        let intent = playbackIntent
        let position = currentTime
        func unchanged() -> Bool {
            !wantsPlayback && !playing && !preparing && !seeking && !closing && seekLoop == nil
                && api.authorizationRevision == authorization && playbackIntent == intent
                && self.session?.id == session.id && self.itemID == itemID && self.episodeID == episodeID
                && currentTime == position
        }
        do {
            guard unchanged(), try await api.currentAccount() == account, unchanged(),
                  try !listening.hasLocalListening(account: account, itemID: itemID, episodeID: episodeID, newerThan: nil) else { return false }
            let user = try await api.me()
            guard unchanged(), try await api.currentAccount() == account, unchanged(),
                  let progress = user.mediaProgress.first(where: { $0.libraryItemId == itemID && $0.episodeId == episodeID }),
                  let remote = progress.currentTime, remote.isFinite, let updated = progress.lastUpdate, updated.isFinite,
                  try !listening.hasLocalListening(account: account, itemID: itemID, episodeID: episodeID, newerThan: updated) else { return false }
            let target = min(max(remote, 0), session.duration)
            guard target != position else { return false }
            try await seek(to: target, autoplay: false)
            return self.session?.id == session.id && currentTime == target
        } catch { return false }
    }

    func restoreListening() async {
        do { try await listening.flush(); clearProgressFailure() }
        catch { failed(error, prefix: "Saved listening is waiting to sync: ", origin: .progress) }
        await resumeProgressResets()
    }

    // Legacy servers timestamp audio and reading together. Publish reading only after
    // listening closes; new audio must wait so this write cannot age unsent listening.
    func publishReading(account: AccountIdentity, itemID: String, location: String, fraction: Double, beforePublication: @escaping @MainActor () throws -> Void) async throws -> Bool {
        guard canPublishReading, readingPublication == nil else { return false }
        let publication = Task { @MainActor in
            try await listening.flush()
            guard try await api.currentAccount() == account else { throw CancellationError() }
            try beforePublication()
            try await api.saveReading(account: account, itemID: itemID, location: location, progress: fraction,
                                      issuing: listening.publications.issuing(account: account, itemID: itemID, episodeID: nil))
        }
        readingPublication = publication
        defer { readingPublication = nil }
        try await publication.value
        return true
    }

    private func clearProgressFailure() {
        if failureOrigin == .progress { error = nil }
    }

    private func failed(_ failure: Error, prefix: String = "", origin: FailureOrigin = .playback) {
        if failure is CancellationError { return }
        if failure as? APIError == .signInRequired { needsSignIn = true }
        error = prefix + failure.localizedDescription
        failureOrigin = origin
    }

    func stop() async throws {
        playbackIntent = UUID()
        interruptedGeneration = nil
        wantsPlayback = false
        cancelSleepTimer()
        try await closeCurrentSession()
    }

    func setFinished(itemID: String, episodeID: String?, finished: Bool) async throws -> CurrentUser {
        let owner = try await api.currentAccount()
        try await prepareProgressEdit(itemID: itemID, episodeID: episodeID)
        try Task.checkCancellation()
        guard try await api.currentAccount() == owner else { throw CancellationError() }
        try await api.setFinished(itemID: itemID, episodeID: episodeID, finished: finished,
                                  issuing: listening.publications.issuing(account: owner, itemID: itemID, episodeID: episodeID))
        let user = try await api.me()
        guard try await api.currentAccount() == owner else { throw CancellationError() }
        try listening.rememberRemoteProgress(user, account: owner)
        return user
    }

    /// Discards the account's progress for the media on this device and the server, as the baseline
    /// Discard progress action does, and returns the refreshed user. `prepare` runs after this
    /// device's listening is published and before anything is changed. The reset is saved before
    /// the server row is deleted; from then until the registered cleanups have discarded this
    /// device's copies, the media cannot be played or its reading published. A reset that fails
    /// after that point throws and is finished by the next attempt, start or `restoreListening`.
    func resetProgress(account: AccountIdentity, itemID: String, episodeID: String?,
                       prepare: @escaping @MainActor () async throws -> Void = {}) async throws -> CurrentUser {
        guard progressReset == nil, !preparing, !closing, !seeking else { throw ProgressResetFailure.busy }
        let authorization = api.authorizationRevision
        func owned() async throws {
            guard api.authorizationRevision == authorization, try await api.currentAccount() == account else { throw CancellationError() }
        }
        let reset = Task { @MainActor () throws -> CurrentUser in
            try await owned()
            if self.itemID == itemID, self.episodeID == episodeID { try await stop() }
            if let readingPublication { _ = try? await readingPublication.value }
            let intent: ProgressResetIntent
            if let pending = try listening.pendingResets().first(where: { $0.covers(account: account, itemID: itemID, episodeID: episodeID) }) {
                // A reset left unfinished is finished, not confirmed again.
                intent = pending
            } else {
                // A write the server may still apply would recreate the row after the delete, and
                // holds back every other write for the media, so only a restart lets this go on.
                @MainActor func unresolved() -> Bool { listening.publications.unresolved(account: account, itemID: itemID, episodeID: episodeID) }
                guard !unresolved() else { throw UnresolvedProgressWrites() }
                // A 2.30 local session sync recreates deleted progress, so unsent listening is
                // published before the delete; if it cannot be, nothing is deleted.
                do {
                    try await listening.flush()
                    try await owned()
                    try await prepare()
                    try await owned()
                } catch where !(error is CancellationError) {
                    // Publishing may have left a write unanswered, or been held back by one.
                    if unresolved() { throw UnresolvedProgressWrites() }
                    throw error
                }
                guard !unresolved() else { throw UnresolvedProgressWrites() }
                guard try !listening.hasLocalListening(account: account, itemID: itemID, episodeID: episodeID, newerThan: nil) else { throw ProgressResetFailure.busy }
                let rowID = try await api.progressRowID(itemID: itemID, episodeID: episodeID, authorization: authorization)
                try await owned()
                guard !unresolved() else { throw UnresolvedProgressWrites() }
                let confirmed = ProgressResetIntent(account: account, itemID: itemID, episodeID: episodeID, rowID: rowID, requestedAt: Date().timeIntervalSince1970 * 1_000)
                try listening.beginReset(confirmed)
                intent = confirmed
            }
            try await finish(intent, authorization: authorization)
            try await owned()
            let user = try await api.me()
            try await owned()
            try listening.rememberRemoteProgress(user, account: account)
            return user
        }
        progressReset = reset
        defer { progressReset = nil }
        return try await reset.value
    }

    /// Registers how another store discards its copies of reset progress. Cleanups run, in no
    /// particular order, whenever a reset finishes, and must tolerate running again.
    func registerProgressResetCleanup(_ name: String, _ cleanup: @escaping @MainActor (ProgressResetIntent) throws -> Void) {
        resetCleanups[name] = cleanup
    }

    /// Whether a confirmed reset of the media has not finished, so its copies must not be published.
    /// Unreadable resets count as pending.
    func progressResetPending(account: AccountIdentity, itemID: String, episodeID: String?) -> Bool {
        guard let resets = try? listening.pendingResets() else { return true }
        return resets.contains { $0.covers(account: account, itemID: itemID, episodeID: episodeID) }
    }

    /// The progress writes this app sends; see `PublicationLedger`.
    var publications: PublicationLedger { listening.publications }

    /// Records that the owner is asked to restart the account's server now; see
    /// `PublicationLedger.requestRestart`.
    func requestServerRestart(account: AccountIdentity) throws {
        try listening.publications.requestRestart(server: account.server)
    }

    /// Records the owner's confirmation that the account's server restarted after the last
    /// `requestServerRestart`, which resolves the writes unresolved at that request.
    func confirmServerRestarted(account: AccountIdentity) throws {
        try listening.publications.confirmRestart(server: account.server)
    }

    /// Finishes the signed-in account's resets that a failure or relaunch left unfinished.
    func resumeProgressResets() async {
        if let progressReset { _ = try? await progressReset.value }
        let authorization = api.authorizationRevision
        guard let account = try? await api.currentAccount(), api.authorizationRevision == authorization else { return }
        do {
            for intent in try listening.pendingResets() where intent.account == account {
                try await finish(intent, authorization: authorization)
            }
        } catch { failed(error, origin: .progress) }
    }

    /// Finishes an unfinished reset of the media before it plays; throws while it cannot.
    private func finishProgressReset(account: AccountIdentity, itemID: String, episodeID: String?) async throws {
        guard let intent = try listening.pendingResets().first(where: { $0.covers(account: account, itemID: itemID, episodeID: episodeID) }) else { return }
        try await finish(intent, authorization: api.authorizationRevision)
    }

    // Deleting the row again is harmless, and cleanups keep copies dated after the confirmation, so
    // a reset can be finished any number of times.
    private func finish(_ intent: ProgressResetIntent, authorization: UUID) async throws {
        do {
            guard api.authorizationRevision == authorization, try await api.currentAccount() == intent.account else { throw CancellationError() }
            if let rowID = intent.rowID { try await api.deleteProgress(rowID: rowID, authorization: authorization) }
            try listening.forgetPosition(account: intent.account, itemID: intent.itemID, episodeID: intent.episodeID, at: intent.requestedAt)
            for cleanup in resetCleanups.values { try cleanup(intent) }
            try listening.finishReset(intent)
        } catch is CancellationError { throw CancellationError() }
        catch { throw ProgressResetFailure.unfinished(error) }
    }

    /// Thrown by `resetProgress` while the server may still apply an earlier write for the media.
    /// Nothing was changed. Server 2.30 cannot confirm when such a write has finished; restarting
    /// it ends the write, and `requestServerRestart` and `confirmServerRestarted` record that.
    struct UnresolvedProgressWrites: LocalizedError {
        var errorDescription: String? {
            "Progress was kept. An earlier save of this title's progress got no answer, and the server may still apply it, which would bring the progress back after it is discarded. Ask for a restart here, restart the Audiobookshelf server, confirm it, then discard again."
        }
    }

    private enum ProgressResetFailure: LocalizedError {
        case busy
        case unfinished(Error)
        var errorDescription: String? {
            switch self {
            case .busy: return "Progress can be discarded once playback and listening sync finish. Try again."
            case .unfinished(let error): return "Discarding progress has not finished, so this title stays on hold until it does. Try again. " + error.localizedDescription
            }
        }
    }

    func prepareProgressEdit(itemID: String, episodeID: String?) async throws {
        if self.itemID == itemID, self.episodeID == episodeID { try await stop() }
        try await listening.flush()
    }

    func suspendForConnectionChange(preservingIntent: UUID? = nil) async throws {
        guard !closing else { throw CancellationError() }
        if preservingIntent == nil { wantsPlayback = false }
        playbackIntent = preservingIntent ?? UUID()
        interruptedGeneration = nil
        pausedAt = nil
        cancelSleepTimer()
        tick(player.currentTime())
        closing = true
        defer { closing = false }
        preparationID = UUID()
        preparing = false
        generation = UUID()
        pendingSeek = nil
        seekLoop?.cancel()
        player.currentItem?.cancelPendingSeeks()
        if let seekLoop { _ = try? await seekLoop.value }
        player.pause()
        playing = false
        syncTask?.cancel()
        await listening.cancelTransfers()
        if let syncTask { await syncTask.value }
        if let listeningID { try listening.finish(id: listeningID) }
        if let session, offlineID == nil { try api.releaseStream(sessionID: session.id) }
        player.replaceCurrentItem(with: nil)
        offlineID = nil; offlineFiles = nil
        session = nil; itemID = nil; episodeID = nil; currentTime = 0; listeningID = nil
        bookmarks = []; bookmarkError = nil
        error = nil
        needsSignIn = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func closeCurrentSession() async throws {
        playbackIntent = UUID()
        interruptedGeneration = nil
        pausedAt = nil
        cancelSleepTimer()
        tick(player.currentTime())
        closing = true
        defer { closing = false }
        generation = UUID()
        pendingSeek = nil
        seekLoop?.cancel()
        player.currentItem?.cancelPendingSeeks()
        if let seekLoop { _ = try? await seekLoop.value }
        player.pause()
        playing = false
        let local = offlineID != nil
        if local {
            syncTask?.cancel()
            await listening.cancelTransfers()
        }
        if let syncTask { await syncTask.value }
        if let session {
            if local {
                if let listeningID { try listening.finish(id: listeningID) }
                Task { await restoreListening() }
            } else {
                try await listening.flush()
                try await api.closeStream(sessionID: session.id)
                if let listeningID { try listening.finish(id: listeningID) }
            }
        }
        generation = UUID()
        player.replaceCurrentItem(with: nil)
        offlineID = nil; offlineFiles = nil
        session = nil; itemID = nil; episodeID = nil; currentTime = 0; listeningID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    nonisolated private static func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let audio = AVAudioSession.sharedInstance()
                    try audio.setCategory(.playback, mode: .spokenAudio)
                    try audio.setActive(true)
                    completion.resume()
                } catch { completion.resume(throwing: error) }
            }
        }
    }

    var mediaChapterWindow: (start: Double, end: Double)? {
        guard chapterTrack, let session, let chapter = currentChapter,
              chapter.start.isFinite, chapter.end.isFinite, chapter.start >= 0,
              chapter.end > chapter.start, chapter.start < session.duration else { return nil }
        return (chapter.start, min(chapter.end, session.duration))
    }

    private func updateNowPlaying() {
        guard let session else { return }
        let window = mediaChapterWindow
        var information: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: window.map { $0.end - $0.start } ?? session.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: window.map { min(max(currentTime - $0.start, 0), $0.end - $0.start) } ?? currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0
        ]
        if window != nil, let chapter = currentChapter, let chapters = session.chapters,
           let index = chapters.lastIndex(where: { $0.id == chapter.id && $0.start == chapter.start && $0.end == chapter.end }) {
            information[MPMediaItemPropertyTitle] = chapter.title.isEmpty ? title : chapter.title
            information[MPNowPlayingInfoPropertyChapterNumber] = index + 1
            information[MPNowPlayingInfoPropertyChapterCount] = chapters.count
        }
        if let nowPlayingArtwork { information[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = information
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            var reason: UInt?
            if #available(iOS 14.5, tvOS 14.5, *) {
                reason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            }
            Task { @MainActor in
                guard let self, let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                if interruption == .began {
                    var suspended = false
                    if #available(iOS 14.5, tvOS 14.5, *) {
                        suspended = reason == AVAudioSession.InterruptionReason.appWasSuspended.rawValue
                    }
                    let resumeGeneration = self.wantsPlayback && !suspended ? self.generation : nil
                    self.pause()
                    self.interruptedGeneration = resumeGeneration
                } else {
                    let resumeGeneration = self.interruptedGeneration
                    self.interruptedGeneration = nil
                    guard resumeGeneration == self.generation,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume), self.session != nil else { return }
                    let intent = self.playbackIntent
                    do {
                        try await Self.activateAudioSession()
                        guard resumeGeneration == self.generation, intent == self.playbackIntent, !self.wantsPlayback else { return }
                        self.resume()
                    } catch { self.failed(error) }
                }
            }
        })
        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
    }

    func loadBookmarks() async {
        guard bookmarkSupported, let id = itemID else { return }
        let request = generation
        do {
            let user = try await api.me()
            guard generation == request else { return }
            bookmarks = (user.bookmarks ?? []).filter { $0.libraryItemId == id }.sorted { $0.time < $1.time }
            bookmarkError = nil
        } catch { if generation == request { bookmarkError = error.localizedDescription } }
    }

    func saveBookmark(title: String, editing: Bookmark?) async {
        guard bookmarkSupported, !bookmarkBusy, let id = itemID else { return }
        let request = generation
        bookmarkBusy = true
        defer { bookmarkBusy = false }
        do {
            try await api.saveBookmark(itemID: id, time: editing?.time ?? floor(currentTime), title: title, editing: editing != nil)
            guard generation == request else { return }
            await loadBookmarks()
        } catch { if generation == request { bookmarkError = error.localizedDescription } }
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        guard !bookmarkBusy, itemID == bookmark.libraryItemId else { return }
        let request = generation
        bookmarkBusy = true
        defer { bookmarkBusy = false }
        do {
            try await api.deleteBookmark(itemID: bookmark.libraryItemId, time: bookmark.time)
            guard generation == request else { return }
            await loadBookmarks()
        } catch { if generation == request { bookmarkError = error.localizedDescription } }
    }

    func setSleepTimer(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        cancelSleepTimer()
        sleepLength = seconds
        sleepRemaining = seconds
        sleepTick = Date()
        sleepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self, let remaining = self.sleepRemaining else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(self.sleepTick)
                self.sleepTick = now
                guard self.player.timeControlStatus == .playing else { continue }
                let updated = max(0, remaining - max(elapsed, 0))
                self.sleepRemaining = updated
                if self.fadeSleepTimer, updated < 60 {
                    if self.fadeStartPosition == nil { self.fadeStartPosition = self.currentTime }
                    self.player.volume = Float(min(updated / 60, 1))
                }
                if updated <= 0 { self.endSleepTimer(); return }
            }
        }
    }

    func setChapterSleepTimer() {
        guard let chapter = currentChapter else { return }
        cancelSleepTimer()
        sleepChapterEnd = chapter.end
        installSleepBoundary()
    }

    func resetSleepTimer() {
        if let seconds = sleepLength { setSleepTimer(seconds: seconds) }
        else if sleepChapterEnd != nil { setChapterSleepTimer() }
    }

    func adjustSleepTimer(by seconds: Double) {
        guard seconds.isFinite, let remaining = sleepRemaining else { return }
        sleepRemaining = max(0, remaining + seconds)
        sleepTick = Date()
        if sleepRemaining == 0 { endSleepTimer() }
        else if (sleepRemaining ?? 0) >= 60 { player.volume = 1; fadeStartPosition = nil }
    }

    func cancelSleepTimer() {
        sleepID = UUID()
        sleepTask?.cancel(); sleepTask = nil
        if let sleepBoundary { player.removeTimeObserver(sleepBoundary) }
        sleepBoundary = nil
        sleepRemaining = nil; sleepChapterEnd = nil; sleepLength = nil
        fadeStartPosition = nil
        player.volume = 1
    }

    private func installSleepBoundary() {
        if let sleepBoundary { player.removeTimeObserver(sleepBoundary) }
        sleepBoundary = nil
        guard let end = sleepChapterEnd, let session, let item = player.currentItem else { return }
        let track = session.audioTracks[trackIndex]
        guard end >= track.startOffset, end <= track.startOffset + track.duration else { return }
        let time = CMTime(seconds: end - track.startOffset, preferredTimescale: 600)
        let timerID = sleepID
        sleepBoundary = player.addBoundaryTimeObserver(forTimes: [NSValue(time: time)], queue: .main) { [weak self] in
            Task { @MainActor in
                guard let self, !self.seeking, self.sleepID == timerID,
                      self.player.currentItem === item, self.sleepChapterEnd == end,
                      self.player.currentTime().seconds + track.startOffset >= end - 0.05 else { return }
                self.endSleepTimer()
            }
        }
    }

    private func endSleepTimer() {
        let rewindPosition = fadeStartPosition
        let timerGeneration = generation
        pause()
        cancelSleepTimer()
        let stoppedIntent = playbackIntent
        if let rewindPosition {
            Task {
                guard generation == timerGeneration, playbackIntent == stoppedIntent, !wantsPlayback else { return }
                do { try await seek(to: rewindPosition, autoplay: false) } catch { failed(error) }
            }
        }
    }
}

#if os(iOS)
extension ApplePlayback {
    /// The mobile reset: carried-over legacy listening is delivered first. Reading positions and
    /// carried-over positions are discarded by the cleanups their stores register.
    func resetProgress(account: AccountIdentity, itemID: String, episodeID: String?, adoption: NativeMigrationAdoption) async throws -> CurrentUser {
        try await resetProgress(account: account, itemID: itemID, episodeID: episodeID,
                                prepare: { try await adoption.prepareProgressReset(account: account, itemID: itemID, episodeID: episodeID) })
    }
}
#endif
