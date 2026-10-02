import Foundation

/// A server 2.30 Socket.IO event the native clients act on, accepted only when it belongs to `owner`.
public enum RealtimeChange {
    /// Authenticated `init`. Server 2.30 does not replay earlier events, so whatever changed before it, since an API load
    /// or while the stream was down, has to be read again.
    case authenticated
    case progress(itemID: String, episodeID: String?, sessionID: String?)
    /// `user_updated`: the owner's progress, bookmarks or permissions changed through the REST API.
    case user
    case itemsUpdated([LibraryItem])
    case itemsAdded(libraryIDs: Set<String>)
    case itemRemoved(id: String)
    case group(kind: AudioGroupKind, id: String, removed: Bool)
    case episodeDownloadFinished(PodcastDownload)
    /// `rss_feed_open` or `rss_feed_closed` (`nil`) for an item, sent to every authenticated client.
    case itemFeed(itemID: String, feed: RSSFeed?)

    public init?(_ event: ServerEvent, owner: AccountIdentity) {
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type) -> T? { try? decoder.decode(type, from: event.data) }
        switch event.name {
        case "init":
            guard decode(Authenticated.self)?.userId == owner.userID else { return nil }
            self = .authenticated
        case "user_item_progress_updated":
            guard let payload = decode(ProgressPayload.self), !payload.data.libraryItemId.isEmpty, payload.data.userId.map({ $0 == owner.userID }) ?? true else { return nil }
            self = .progress(itemID: payload.data.libraryItemId, episodeID: payload.data.episodeId, sessionID: payload.sessionId)
        case "user_updated":
            guard decode(Identity.self)?.id == owner.userID else { return nil }
            self = .user
        case "item_updated":
            guard let item = decode(LibraryItem.self) else { return nil }
            self = .itemsUpdated([item])
        case "items_updated":
            guard let items = decode([LibraryItem].self) else { return nil }
            self = .itemsUpdated(items)
        case "item_added":
            guard let item = decode(Placed.self) else { return nil }
            self = .itemsAdded(libraryIDs: [item.libraryId])
        case "items_added":
            guard let items = decode([Placed].self) else { return nil }
            self = .itemsAdded(libraryIDs: Set(items.map(\.libraryId)))
        case "item_removed":
            guard let item = decode(Identity.self) else { return nil }
            self = .itemRemoved(id: item.id)
        case "playlist_added", "playlist_updated", "playlist_removed", "collection_added", "collection_updated", "collection_removed":
            guard let group = decode(Owned.self), group.userId.map({ $0 == owner.userID }) ?? true else { return nil }
            self = .group(kind: event.name.hasPrefix("playlist") ? .playlist : .collection, id: group.id, removed: event.name.hasSuffix("_removed"))
        case "rss_feed_open", "rss_feed_closed":
            guard let entity = decode(FeedEntity.self), entity.entityType == "libraryItem" else { return nil }
            if event.name == "rss_feed_closed" { self = .itemFeed(itemID: entity.entityId, feed: nil); return }
            guard let feed = decode(RSSFeed.self) else { return nil }
            self = .itemFeed(itemID: entity.entityId, feed: feed)
        case "episode_download_finished":
            guard let job = decode(PodcastDownload.self) else { return nil }
            self = .episodeDownloadFinished(job)
        default: return nil
        }
    }

    private struct Authenticated: Decodable { let userId: String }
    private struct Identity: Decodable { let id: String }
    private struct Placed: Decodable { let libraryId: String }
    private struct FeedEntity: Decodable { let entityType: String; let entityId: String }
    private struct Owned: Decodable { let id: String; let userId: String? }
    private struct ProgressPayload: Decodable {
        struct Progress: Decodable { let libraryItemId: String; let episodeId: String?; let userId: String? }
        let sessionId: String?
        let data: Progress
    }
}
