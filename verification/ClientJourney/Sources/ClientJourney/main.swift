import Foundation
import TVCore

@MainActor final class JourneyCredentials: CredentialStore {
    private var value: Credentials?
    func load() throws -> Credentials? { value }
    func save(_ credentials: Credentials) throws { value = credentials }
    func clear() throws { value = nil }
}

struct JourneyFailure: Error {
    let workflow: String
    let reason: String
}

@main struct ClientJourney {
    @MainActor static func main() async {
        var workflow = "configuration"
        do {
            guard CommandLine.arguments.count == 2,
                  let url = URL(string: CommandLine.arguments[1]),
                  url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw JourneyFailure(workflow: workflow, reason: "Use a loopback fixture URL. This runner accepts synthetic credentials only.")
            }
            let store = JourneyCredentials()
            let api = APIClient(store: store)
            workflow = "authentication"
            try await api.login(server: url.absoluteString, username: "qa", password: "qa")
            let libraries = try await api.libraries()
            guard libraries.contains(where: { $0.id == "books" }) else {
                throw JourneyFailure(workflow: workflow, reason: "Audiobooks library is missing.")
            }
            workflow = "credential-restoration"
            let restored = APIClient(store: store)
            guard restored.credentials != nil else { throw JourneyFailure(workflow: workflow, reason: "The refreshed account was not persisted.") }
            workflow = "library-pagination"
            let first = try await restored.items(libraryID: "books", page: 0)
            let second = try await restored.items(libraryID: "books", page: 1)
            guard first.total == 61, first.results.count == 60, second.results.map(\.id) == ["book-60"] else {
                throw JourneyFailure(workflow: workflow, reason: "The paginated catalog lost or duplicated an item.")
            }
            workflow = "book-playback"
            let item = try await restored.item(id: "book-60")
            let session = try await restored.play(itemID: item.id, deviceID: "local-compatibility")
            guard session.displayTitle == item.title, session.audioTracks.count == 2,
                  session.position(at: 9)?.trackIndex == 1, session.position(at: 9)?.localTime == 1 else {
                throw JourneyFailure(workflow: workflow, reason: "Book identity or multi-file time mapping changed.")
            }
            workflow = "podcast-playback"
            let podcast = try await restored.item(id: "podcast")
            guard let episode = podcast.media.episodes?.first else { throw JourneyFailure(workflow: workflow, reason: "Podcast episode is missing.") }
            let episodeSession = try await restored.play(itemID: podcast.id, episodeID: episode.id, deviceID: "local-compatibility")
            guard episodeSession.displayTitle == episode.title else { throw JourneyFailure(workflow: workflow, reason: "Podcast episode identity changed.") }
            workflow = "authenticated-media"
            for track in session.audioTracks {
                var request = URLRequest(url: try restored.mediaURL(track.contentUrl))
                request.setValue("Bearer \(try await restored.validToken())", forHTTPHeaderField: "Authorization")
                request.setValue("bytes=0-43", forHTTPHeaderField: "Range")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 206, data.count == 44,
                      String(data: data.prefix(4), encoding: .utf8) == "RIFF" else {
                    throw JourneyFailure(workflow: workflow, reason: "Authenticated media no longer supports the expected byte-range probe.")
                }
            }
            workflow = "progress-close"
            try await restored.report(sessionID: session.id, report: ProgressReport(currentTime: 9, timeListened: 3, duration: session.duration), close: true)
            let reopened = try await APIClient(store: store).play(itemID: item.id, deviceID: "local-compatibility-relaunch")
            guard reopened.currentTime == 9 else { throw JourneyFailure(workflow: workflow, reason: "The server did not retain the closed session's progress for relaunch.") }
            let result: [String: Any] = ["client": "TVCore", "result": "passed", "workflows": ["authentication", "credential-restoration", "library-pagination", "book-playback", "podcast-playback", "authenticated-media", "progress-close"]]
            print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
        } catch {
            // Only workflow and error category are emitted: decoder errors can embed credentials or server data.
            let reason = (error as? JourneyFailure)?.reason ?? (error is DecodingError ? "Server response no longer matches the client's contract." : "Client request failed; inspect the synthetic fixture observations.")
            let result = ["client": "TVCore", "result": "failed", "workflow": workflow, "reason": reason]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                FileHandle.standardError.write(data + Data([10]))
            }
            exit(1)
        }
    }
}
