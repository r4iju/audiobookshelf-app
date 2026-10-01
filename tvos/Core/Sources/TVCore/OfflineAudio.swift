import Foundation

public struct OfflineAudio {
    public let id: String
    public let account: AccountIdentity
    public let media: ListeningMedia
    public let files: [URL]
    public let tracks: [AudioTrack]
    public let chapters: [Chapter]
    public let serverPosition: Double
    public let serverUpdatedAt: Double

    public init(id: String, account: AccountIdentity, media: ListeningMedia, files: [URL], tracks: [AudioTrack], chapters: [Chapter], serverPosition: Double, serverUpdatedAt: Double) {
        self.id = id; self.account = account; self.media = media; self.files = files; self.tracks = tracks
        self.chapters = chapters; self.serverPosition = serverPosition; self.serverUpdatedAt = serverUpdatedAt
    }
}
