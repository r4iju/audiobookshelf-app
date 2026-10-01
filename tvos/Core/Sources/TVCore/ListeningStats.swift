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
    public struct NamedTime: Decodable, Sendable { public let name: String; public let time: Double }
    public struct GenreTime: Decodable, Sendable { public let genre: String; public let time: Double }
    public struct MonthTime: Decodable, Sendable { public let month: Int; public let time: Double }
    public struct FinishedBook: Decodable, Sendable { public let title: String; public let duration: Double }
}
