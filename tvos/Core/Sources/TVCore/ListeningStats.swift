import Foundation

public struct ListeningStats: Decodable, Sendable {
    public let totalTime: Double
    public let days: [String: Double]
    public let recentSessions: [ListeningSessionSummary]
}

public struct ListeningSessionSummary: Decodable, Identifiable, Sendable {
    public let id: String
    public let libraryItemId: String?
    public let mediaMetadata: Metadata?
    public let timeListening: Double
    public let updatedAt: Double
    private enum CodingKeys: String, CodingKey { case id, libraryItemId, mediaMetadata, timeListening, updatedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        libraryItemId = try values.decodeIfPresent(String.self, forKey: .libraryItemId)
        mediaMetadata = try values.decodeIfPresent(Metadata.self, forKey: .mediaMetadata)
        updatedAt = try values.decode(Double.self, forKey: .updatedAt)
        if let number = try? values.decode(Double.self, forKey: .timeListening) { timeListening = number }
        else {
            let raw = try values.decode(String.self, forKey: .timeListening)
            guard let number = Double(raw), number.isFinite, number >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .timeListening, in: values, debugDescription: "Invalid listening duration")
            }
            timeListening = number
        }
    }
    public struct Metadata: Decodable, Sendable {
        public let title: String?
        public let authorName: String?
    }
}

public struct YearListeningStats: Decodable, Sendable {
    public let totalListeningSessions: Int
    public let totalListeningTime: Double
    public let totalBookListeningTime: Double
    public let totalPodcastListeningTime: Double
    public let numBooksFinished: Int
    public let numBooksListened: Int
    public let topAuthors: [NamedTime]
    public let topGenres: [GenreTime]
    public let mostListenedNarrator: NamedTime?
    public let mostListenedMonth: MonthTime?
    public let longestAudiobookFinished: FinishedBook?
    /// Library item IDs, in server order. Finished books never repeat in `booksWithCovers`.
    public let finishedBooksWithCovers: [String]
    public let booksWithCovers: [String]
    public struct NamedTime: Decodable, Sendable { public let name: String; public let time: Double }
    public struct GenreTime: Decodable, Sendable { public let genre: String; public let time: Double }
    public struct MonthTime: Decodable, Sendable { public let month: Int; public let time: Double }
    public struct FinishedBook: Decodable, Sendable { public let title: String; public let duration: Double }

    private enum CodingKeys: String, CodingKey {
        case totalListeningSessions, totalListeningTime, totalBookListeningTime, totalPodcastListeningTime, numBooksFinished, numBooksListened
        case topAuthors, topGenres, mostListenedNarrator, mostListenedMonth, longestAudiobookFinished, finishedBooksWithCovers, booksWithCovers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        totalListeningSessions = try values.decode(Int.self, forKey: .totalListeningSessions)
        totalListeningTime = try values.decode(Double.self, forKey: .totalListeningTime)
        totalBookListeningTime = try values.decode(Double.self, forKey: .totalBookListeningTime)
        totalPodcastListeningTime = try values.decode(Double.self, forKey: .totalPodcastListeningTime)
        numBooksFinished = try values.decode(Int.self, forKey: .numBooksFinished)
        numBooksListened = try values.decode(Int.self, forKey: .numBooksListened)
        topAuthors = try values.decode([NamedTime].self, forKey: .topAuthors)
        topGenres = try values.decode([GenreTime].self, forKey: .topGenres)
        mostListenedNarrator = try values.decodeIfPresent(NamedTime.self, forKey: .mostListenedNarrator)
        mostListenedMonth = try values.decodeIfPresent(MonthTime.self, forKey: .mostListenedMonth)
        longestAudiobookFinished = try values.decodeIfPresent(FinishedBook.self, forKey: .longestAudiobookFinished)
        finishedBooksWithCovers = try values.decodeIfPresent([String].self, forKey: .finishedBooksWithCovers) ?? []
        booksWithCovers = try values.decodeIfPresent([String].self, forKey: .booksWithCovers) ?? []
    }
}

/// `GET /api/stats/year/:year`, available to admin and root accounts only.
public struct ServerYearStats: Decodable, Sendable {
    public let numListeningSessions: Int
    public let numBooksAdded: Int
    public let numAuthorsAdded: Int
    public let numBooks: Int
    public let totalBooksAddedSize: Double
    public let totalBooksAddedDuration: Double
    public let totalBooksSize: Double
    public let totalBooksDuration: Double
    public let totalListeningTime: Double
    /// Library item IDs of books added this year, in server order.
    public let booksAddedWithCovers: [String]
    public let topAuthors: [YearListeningStats.NamedTime]
    public let topNarrators: [YearListeningStats.NamedTime]
    public let topGenres: [YearListeningStats.GenreTime]

    private enum CodingKeys: String, CodingKey {
        case numListeningSessions, numBooksAdded, numAuthorsAdded, numBooks, totalBooksAddedSize, totalBooksAddedDuration
        case totalBooksSize, totalBooksDuration, totalListeningTime, booksAddedWithCovers, topAuthors, topNarrators, topGenres
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func total(_ key: CodingKeys) throws -> Double { try values.decodeIfPresent(Double.self, forKey: key) ?? 0 }
        numListeningSessions = try values.decode(Int.self, forKey: .numListeningSessions)
        numBooksAdded = try values.decode(Int.self, forKey: .numBooksAdded)
        numAuthorsAdded = try values.decode(Int.self, forKey: .numAuthorsAdded)
        numBooks = try values.decodeIfPresent(Int.self, forKey: .numBooks) ?? 0
        totalBooksAddedSize = try total(.totalBooksAddedSize)
        totalBooksAddedDuration = try total(.totalBooksAddedDuration)
        totalBooksSize = try total(.totalBooksSize)
        totalBooksDuration = try total(.totalBooksDuration)
        totalListeningTime = try total(.totalListeningTime)
        booksAddedWithCovers = try values.decodeIfPresent([String].self, forKey: .booksAddedWithCovers) ?? []
        topAuthors = try values.decodeIfPresent([YearListeningStats.NamedTime].self, forKey: .topAuthors) ?? []
        topNarrators = try values.decodeIfPresent([YearListeningStats.NamedTime].self, forKey: .topNarrators) ?? []
        topGenres = try values.decodeIfPresent([YearListeningStats.GenreTime].self, forKey: .topGenres) ?? []
    }
}

public extension CurrentUser {
    /// Mirrors the server's `isAdminOrUp` gate on `/api/stats`.
    var canViewServerYearStats: Bool { type == "root" || type == "admin" }
}
