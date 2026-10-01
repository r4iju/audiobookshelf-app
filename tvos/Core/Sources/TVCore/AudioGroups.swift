import Foundation

public enum AudioGroupKind: String {
    case collection = "collections"
    case playlist = "playlists"
    public var title: String { self == .collection ? "Collections" : "Playlists" }
    public var singular: String { self == .collection ? "collection" : "playlist" }
}

public struct AudioGroup: Decodable, Identifiable {
    public let id: String
    public let libraryId: String
    public let name: String
    public let description: String?
    public let userId: String?
    public let books: [LibraryItem]?
    public let items: [AudioGroupMember]?
    public var members: [AudioGroupMember] {
        items ?? (books ?? []).map { AudioGroupMember(libraryItemId: $0.id, libraryItem: $0, episodeId: nil, episode: nil) }
    }
}

public struct AudioGroupMember: Decodable, Identifiable {
    public let libraryItemId: String
    public let libraryItem: LibraryItem?
    public let episodeId: String?
    public let episode: Episode?
    public var id: String { libraryItemId + ":" + (episodeId ?? "") }
    public var title: String { episode?.title ?? libraryItem?.title ?? "Unavailable content" }
    public var playable: Bool {
        guard let item = libraryItem, item.isMissing != true, item.isInvalid != true else { return false }
        if episodeId != nil { return episode?.audioFile != nil || episode?.audioTrack != nil }
        return !(item.media.tracks ?? []).isEmpty
    }
}

public struct AudioGroupPage: Decodable {
    public let results: [AudioGroup]
    public let total: Int
}
