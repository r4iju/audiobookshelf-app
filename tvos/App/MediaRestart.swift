import Foundation

/// What Now Playing needs from the shared player to restart media that failed.
@MainActor protocol RestartablePlayback: AnyObject {
    var session: PlaybackSession? { get }
    var itemID: String? { get }
    var episodeID: String? { get }
    var wantsPlayback: Bool { get }
    var playbackIntentID: UUID { get }
    var error: String? { get }
    var isProgressFailure: Bool { get }
    func start(item: LibraryItem, episode: Episode?) async
}

extension ApplePlayback: RestartablePlayback {}

/// Restarts the media that failed after refetching it, unless anything about that failure changed while waiting.
@MainActor enum MediaRestart {
    /// The failed playback a restart was requested for.
    private struct Failure: Equatable {
        let account: UUID
        let sessionID: String?
        let itemID: String
        let episodeID: String?
        let wantsPlayback: Bool
        let intent: UUID
        let error: String

        @MainActor init?(_ player: RestartablePlayback, account: UUID) {
            guard let itemID = player.itemID, let error = player.error, !player.isProgressFailure else { return nil }
            self.account = account
            sessionID = player.session?.id
            self.itemID = itemID
            episodeID = player.episodeID
            wantsPlayback = player.wantsPlayback
            intent = player.playbackIntentID
            self.error = error
        }
    }

    /// Returns the message to show, or nil when the restart ran or no longer applies.
    static func run(_ player: RestartablePlayback, account: @escaping () -> UUID, fetch: (String) async throws -> LibraryItem) async -> String? {
        guard let failure = Failure(player, account: account()) else { return nil }
        let unchanged = { Failure(player, account: account()) == failure }
        do {
            let item = try await fetch(failure.itemID)
            guard unchanged() else { return nil }
            let episode = failure.episodeID.flatMap { id in item.media.episodes?.first { $0.id == id } }
            if failure.episodeID != nil, episode == nil { return "This episode is no longer on the server." }
            await player.start(item: item, episode: episode)
            return nil
        } catch {
            guard unchanged() else { return nil }
            return "Playback could not be restarted: " + CatalogStore.recovery(for: error)
        }
    }
}
