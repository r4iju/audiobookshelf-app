import Foundation

public enum APIError: Error, LocalizedError, Equatable {
    case invalidServer, unsafeMediaURL, signInRequired, http(Int), noAudio, invalidPodcastTitle, podcastRequestTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidServer: return CoreText.text("Enter an http:// or https:// server address, without credentials, a query, or a fragment.")
        case .unsafeMediaURL: return CoreText.text("The server returned a media URL outside this server.")
        case .signInRequired: return CoreText.text("Your session expired. Please sign in again.")
        case .http(401): return CoreText.text("The username or password was not accepted.")
        case .http(let code): return CoreText.text("The server returned HTTP {0}. Please try again.", code)
        case .noAudio: return CoreText.text("This item has no playable audio.")
        case .invalidPodcastTitle: return CoreText.text("Enter a podcast title that can name a folder on your server.")
        case .podcastRequestTooLarge: return CoreText.text("Select fewer feed episodes and try again. The server accepts requests smaller than 5 MB.")
        }
    }
}

public struct ServerAddress: Sendable {
    public let base: URL
    public init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let base = parts.url else { throw APIError.invalidServer }
        self.base = base
    }

    public func url(path: String, query: [URLQueryItem] = []) throws -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let prefix = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + [prefix, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        parts.queryItems = query.isEmpty ? nil : query
        // Express treats a literal plus as a space when it parses the query.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw APIError.invalidServer }
        return url
    }

    public func mediaURL(_ path: String) throws -> URL {
        guard !path.hasPrefix("//"), let relative = URLComponents(string: path) else { throw APIError.unsafeMediaURL }
        if relative.scheme != nil {
            guard let url = relative.url, url.scheme == base.scheme, url.host == base.host,
                  url.port == base.port, relative.user == nil, relative.password == nil else { throw APIError.unsafeMediaURL }
            return url
        }
        guard relative.host == nil else { throw APIError.unsafeMediaURL }
        return try url(path: relative.path, query: relative.queryItems ?? [])
    }
}

public struct Credentials: Codable, Sendable {
    public let server: String
    public let accessToken: String
    public let refreshToken: String?
    public let userID: String?
    public let username: String?
    public init(server: String, accessToken: String, refreshToken: String?, userID: String? = nil, username: String? = nil) {
        self.server = server; self.accessToken = accessToken; self.refreshToken = refreshToken
        self.userID = userID; self.username = username
    }
}

@MainActor public protocol CredentialStore {
    func load() throws -> Credentials?
    func save(_ credentials: Credentials) throws
    func replace(_ credentials: Credentials, replacing original: Credentials) throws
    func clear() throws
}

public extension CredentialStore {
    func replace(_ credentials: Credentials, replacing original: Credentials) throws { try save(credentials) }
}

public struct AuthResponse: Decodable {
    public let user: AuthUser
}
public struct AuthUser: Decodable {
    public let id: String?
    public let username: String?
    public let token: String?
    public let accessToken: String?
    public let refreshToken: String?
    public var bearerToken: String? { accessToken ?? token }
}

public struct Library: Decodable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let mediaType: String
    public let folders: [LibraryFolder]?
}
public struct LibraryFolder: Decodable, Identifiable, Hashable {
    public let id: String
    public let fullPath: String
}
public struct LibrariesResponse: Decodable { public let libraries: [Library] }
public struct ItemsResponse: Decodable {
    public let results: [LibraryItem]
    public let total: Int
}
public struct LibraryItem: Decodable, Identifiable, Hashable {
    public let id: String
    public let libraryId: String?
    public let isMissing: Bool?
    public let isInvalid: Bool?
    public let mediaType: String
    public let media: Media
    public let recentEpisode: Episode?
    public let libraryFiles: [LibraryFile]?
    public var supplementaryEbooks: [LibraryFile] { (libraryFiles ?? []).filter { $0.ebook != nil && $0.ino != media.ebookFile?.ino } }
    public var title: String { media.metadata.title }
    public var author: String { media.metadata.authorName ?? media.metadata.author ?? media.metadata.authors?.map(\.name).joined(separator: ", ") ?? "" }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
public struct Media: Decodable {
    public let metadata: Metadata
    public let duration: Double?
    public let episodes: [Episode]?
    public let chapters: [Chapter]?
    public let tracks: [AudioTrack]?
    public let ebookFile: EbookFile?
}
public struct EbookFile: Codable {
    public let ino: String
    public let ebookFormat: String
    public let metadata: AudioTrack.TrackMetadata?
    public var format: String { ebookFormat.lowercased() }
}
public struct LibraryFile: Codable, Identifiable {
    public let ino: String
    public let fileType: String
    public let metadata: AudioTrack.TrackMetadata?
    public var id: String { ino }
    public var ebook: EbookFile? {
        guard fileType == "ebook" else { return nil }
        let format = (metadata?.ext ?? (metadata?.filename as NSString?)?.pathExtension ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return EbookFile(ino: ino, ebookFormat: format, metadata: metadata)
    }
}
public struct Metadata: Decodable {
    public let title: String
    public let authorName: String?
    public let author: String?
    public let authors: [Author]?
    public let description: String?
    public let narrators: [String]?
    public let genres: [String]?
    public let feedUrl: String?
    public let seriesName: String?
    let series: SeriesReferences?
}
public struct Author: Decodable { public let id: String?; public let name: String }
public struct Episode: Decodable, Identifiable {
    public let id: String
    public let title: String
    public let duration: Double?
    public let description: String?
    public let publishedAt: Double?
    public let season: String?
    public let episode: String?
    public let chapters: [Chapter]?
    public let audioTrack: AudioTrack?
    public let audioFile: File?
    public let enclosure: Enclosure?
    public struct Enclosure: Decodable { public let url: String? }
    public struct File: Decodable {
        public let duration: Double?
        public let metadata: FileMetadata?
        public struct FileMetadata: Decodable { public let filename: String? }
    }
}
public struct Chapter: Codable, Identifiable {
    public let id: Int
    public let title: String
    public let start: Double
    public let end: Double
}
public struct AudioTrack: Codable, Sendable {
    public let contentUrl: String
    public var mimeType: String? = nil
    public let metadata: TrackMetadata?
    public struct TrackMetadata: Codable, Sendable {
        public let filename: String?
        public let ext: String?
        /// The file's size on the server in bytes, when the server lists it (2.30 does for audio and ebook files).
        public var size: Int64? = nil
    }
    public let startOffset: Double
    public let duration: Double
}
public struct PlaybackSession: Decodable {
    public let id: String
    public let currentTime: Double
    public let duration: Double
    public let audioTracks: [AudioTrack]
    public let chapters: [Chapter]?
    public let displayTitle: String?
    public let displayAuthor: String?

    public struct Position {
        public let trackIndex: Int
        public let localTime: Double
    }
    public func position(at time: Double) -> Position? {
        guard !audioTracks.isEmpty else { return nil }
        let safe = min(max(time.isFinite ? time : 0, 0), duration)
        let index = audioTracks.lastIndex(where: { $0.startOffset <= safe }) ?? 0
        let track = audioTracks[index]
        return Position(trackIndex: index, localTime: min(max(safe - track.startOffset, 0), track.duration))
    }
}
public struct ProgressReport: Codable {
    public let currentTime: Double
    public let timeListened: Double
    public let duration: Double
    public init(currentTime: Double, timeListened: Double, duration: Double) {
        self.currentTime = currentTime; self.timeListened = timeListened; self.duration = duration
    }
}

public struct CurrentUser: Decodable {
    public let id: String
    public let username: String
    public let type: String?
    public var canManagePodcasts: Bool { type == "root" || type == "admin" }
    public let mediaProgress: [MediaProgress]
    public let permissions: UserPermissions
    public let bookmarks: [Bookmark]?
}

public struct PodcastFeedResponse: Decodable {
    public let podcast: PodcastFeed
}
public struct PodcastDiscovery: Decodable, Identifiable {
    public let id: Int
    public let title: String
    public let artistName: String?
    public let descriptionPlain: String?
    public let feedUrl: String?
    public let cover: String?
    public let genres: [String]?
    public let releaseDate: String?
    public let pageUrl: String?
    public let artistId: Int?
}
public struct PodcastFeed: Decodable {
    public let metadata: FeedMetadata
    public let episodes: [PodcastFeedEpisode]?
    public struct FeedMetadata: Decodable {
        public let title: String?
        public let author: String?
        public let descriptionPlain: String?
        public let feedUrl: String?
        public let image: String?
        public let categories: [String]?
    }
}

public struct PodcastDownloads: Decodable {
    public let downloads: [PodcastDownload]
}
public struct PodcastDownload: Decodable, Identifiable {
    public let id: String
    public let libraryItemId: String?
    public let episodeDisplayTitle: String?
    public let isFinished: Bool
    public let failed: Bool
    public let url: String?
}

public struct Bookmark: Decodable, Identifiable {
    public let libraryItemId: String
    public let time: Double
    public let title: String
    public var id: String { libraryItemId + ":" + String(time) }
}

public struct SearchResponse: Decodable {
    public struct Item: Decodable { public let libraryItem: LibraryItem }
    public struct EpisodeResult: Decodable, Identifiable {
        public let libraryItem: LibraryItem
        public var id: String { libraryItem.recentEpisode?.id ?? libraryItem.id }
    }
    public struct AuthorMatch: Decodable, Identifiable { public let id: String; public let name: String }
    public struct NamedMatch: Decodable, Identifiable { public let name: String; public var id: String { name } }
    public struct SeriesMatch: Decodable, Identifiable {
        public let series: AuthorMatch
        public let books: [LibraryItem]
        public var id: String { series.id }
    }
    public let book: [Item]?
    public let podcast: [Item]?
    public let episodes: [EpisodeResult]?
    public let authors: [AuthorMatch]?
    public let series: [SeriesMatch]?
    public let narrators: [NamedMatch]?
    public let tags: [NamedMatch]?
    public var items: [LibraryItem] { (book ?? []).map(\.libraryItem) + (podcast ?? []).map(\.libraryItem) }
    public var isEmpty: Bool { items.isEmpty && (episodes ?? []).isEmpty && (authors ?? []).isEmpty && (series ?? []).isEmpty && (narrators ?? []).isEmpty && (tags ?? []).isEmpty }
}

public struct LibraryFilters: Decodable {
    public let authors: [SearchResponse.AuthorMatch]?
    public let series: [SearchResponse.AuthorMatch]?
    public let genres: [String]?
    public let tags: [String]?
    public let narrators: [String]?
    public let languages: [String]?
}

public struct UserPermissions: Decodable {
    public let accessExplicitContent: Bool?
    public let download: Bool?
    public let update: Bool?
    public let delete: Bool?
    public let upload: Bool?
}

public struct MediaProgress: Codable, Identifiable {
    public let libraryItemId: String
    public let episodeId: String?
    public let currentTime: Double?
    public let duration: Double?
    public let progress: Double?
    public let isFinished: Bool?
    public let ebookLocation: String?
    public let ebookProgress: Double?
    public let lastUpdate: Double?
    public var id: String { libraryItemId + ":" + (episodeId ?? "book") }
    public var fraction: Double { min(max(progress ?? 0, 0), 1) }
}

public struct PersonalizedShelf: Decodable {
    public let id: String
    public let type: String
    public let entities: [LibraryItem]
    private enum CodingKeys: String, CodingKey { case id, type, entities }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        entities = type == "book" || type == "podcast" ? try values.decode([LibraryItem].self, forKey: .entities) : []
    }
}
