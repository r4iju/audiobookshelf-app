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
