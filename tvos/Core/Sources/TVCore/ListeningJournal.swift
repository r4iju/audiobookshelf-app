import Foundation

public struct AccountIdentity: Codable, Hashable, Sendable {
    public let server: String
    public let userID: String

    public init(server: String, userID: String) throws {
        guard !userID.isEmpty else { throw APIError.signInRequired }
        var address = URLComponents(url: try ServerAddress(server).base, resolvingAgainstBaseURL: false)!
        address.scheme = address.scheme?.lowercased()
        address.host = address.host?.lowercased()
        if address.scheme == "https" && address.port == 443 || address.scheme == "http" && address.port == 80 { address.port = nil }
        while address.path.hasSuffix("/") { address.path.removeLast() }
        self.server = address.url!.absoluteString
        self.userID = userID
    }
}

public struct ListeningMedia: Codable, Sendable {
    public let libraryItemID: String
    public let episodeID: String?
    public let title: String
    public let author: String
    public let mediaType: String
    public let duration: Double
    public let startTime: Double

    public init(item: LibraryItem, episode: Episode? = nil, session: PlaybackSession) {
        libraryItemID = item.id
        episodeID = episode?.id
        title = episode?.title ?? item.title
        author = item.author
        mediaType = item.mediaType
        duration = session.duration
        startTime = session.currentTime
    }
}

public struct ListeningRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let account: AccountIdentity
    public let media: ListeningMedia
    public let deviceID: String
    public let startedAt: Double
    public fileprivate(set) var updatedAt: Double
    public fileprivate(set) var currentTime: Double
    public fileprivate(set) var timeListening: Double
    fileprivate var revision: UInt64
    fileprivate var acknowledged: UInt64
    fileprivate var closed: Bool

    var payload: [String: Any] {
        ["id": id, "libraryItemId": media.libraryItemID, "episodeId": media.episodeID as Any? ?? NSNull(),
         "mediaType": media.mediaType, "mediaMetadata": ["title": media.title, "authorName": media.author],
         "displayTitle": media.title, "displayAuthor": media.author, "duration": media.duration,
         "playMethod": 0, "mediaPlayer": "AVPlayer", "startTime": media.startTime,
         "currentTime": currentTime, "timeListening": timeListening, "startedAt": startedAt, "updatedAt": updatedAt]
    }
}

@MainActor public final class ListeningJournal {
    private struct Document: Codable {
        let version: Int
        var records: [ListeningRecord]
    }
    public enum Failure: LocalizedError {
        case invalidData
        public var errorDescription: String? { "Saved listening data could not be read or updated. Keep the app's data for recovery and try again." }
    }
    private let file: URL
    private var records: [ListeningRecord]

    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let saved = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
            guard saved.version == 1 else { throw Failure.invalidData }
            records = saved.records
        } else { records = [] }
    }

    public func begin(account: AccountIdentity, media: ListeningMedia, deviceID: String, at date: Date = Date()) throws -> String {
        guard media.duration.isFinite, media.duration > 0, media.startTime.isFinite else { throw Failure.invalidData }
        let id = UUID().uuidString.lowercased()
        let time = date.timeIntervalSince1970 * 1000
        let record = ListeningRecord(id: id, account: account, media: media, deviceID: deviceID, startedAt: time, updatedAt: time,
                                     currentTime: min(max(media.startTime, 0), media.duration), timeListening: 0, revision: 1, acknowledged: 0, closed: false)
        try commit(records + [record])
        return id
    }

    public func record(id: String, position: Double, listened: Double, at date: Date = Date()) throws {
        guard position.isFinite, listened.isFinite, listened >= 0,
              let index = records.firstIndex(where: { $0.id == id }), !records[index].closed else { throw Failure.invalidData }
        var next = records
        next[index].currentTime = min(max(position, 0), next[index].media.duration)
        next[index].timeListening += listened
        next[index].updatedAt = date.timeIntervalSince1970 * 1000
        guard next[index].timeListening.isFinite, next[index].revision < .max else { throw Failure.invalidData }
        next[index].revision += 1
        try commit(next)
    }

    public func finish(id: String) throws {
        guard let index = records.firstIndex(where: { $0.id == id }), !records[index].closed else { return }
        var next = records
        next[index].closed = true
        if next[index].acknowledged == next[index].revision { next.remove(at: index) }
        try commit(next)
    }

    public func pending(account: AccountIdentity) -> [ListeningRecord] {
        records.filter { $0.account == account && $0.revision > $0.acknowledged }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt }
    }

    public func acknowledge(_ sent: ListeningRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == sent.id && $0.account == sent.account }) else { return }
        var next = records
        next[index].acknowledged = max(next[index].acknowledged, min(sent.revision, next[index].revision))
        if next[index].closed && next[index].acknowledged == next[index].revision { next.remove(at: index) }
        try commit(next)
    }

    public func finishRecoveredSessions() throws {
        var next = records
        for index in next.indices where !next[index].closed {
            next[index].closed = true
        }
        next.removeAll { $0.closed && $0.revision == $0.acknowledged }
        try commit(next)
    }

    private func commit(_ next: [ListeningRecord]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(version: 1, records: next))
        var options: Data.WritingOptions = .atomic
        #if os(iOS) || os(tvOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: file, options: options)
        records = next
    }
}
