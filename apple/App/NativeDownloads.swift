import Foundation
import Combine
import UIKit

// The session uses the serial main queue so UIKit completion follows durable file publication.
// Temporary download files must move before the download callback returns.
@MainActor private final class DownloadDelegate: NSObject, @preconcurrency URLSessionDownloadDelegate {
    weak var owner: NativeDownloads?
    private var staged: [Int: URL] = [:]
    private var failures: [Int: Error] = [:]
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let target = NativeDownloads.directory.appendingPathComponent("staging-" + UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: target)
            staged[downloadTask.taskIdentifier] = target
        } catch { failures[downloadTask.taskIdentifier] = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let file = staged.removeValue(forKey: task.taskIdentifier)
        let failure = failures.removeValue(forKey: task.taskIdentifier) ?? error
        owner?.completed(task: task, file: file, error: failure)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        owner?.progress(task: downloadTask, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = NativeDownloadAppDelegate.backgroundCompletion
        NativeDownloadAppDelegate.backgroundCompletion = nil
        completion?()
    }
}

final class NativeDownloadAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var backgroundCompletion: (() -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Self.backgroundCompletion = completionHandler
    }
}

@MainActor final class NativeDownloads: ObservableObject {
    private enum Failure: LocalizedError {
        case invalidAudio
        var errorDescription: String? { "The server returned a page instead of audio. Check the server and retry the download." }
    }
    enum State: String, Codable { case queued, ready, failed, cancelled }
    struct Entry: Codable, Identifiable {
        let id: String
        let account: AccountIdentity
        let media: ListeningMedia
        let tracks: [AudioTrack]
        let chapters: [Chapter]
        let serverPosition: Double
        let serverUpdatedAt: Double
        var generation: String
        var finished: [Int]
        var state: State
        var error: String?
    }
    private struct Manifest: Codable { let version: Int; let entries: [Entry] }
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDownloads", isDirectory: true)
    }
    private static let sessionID = "com.forkzed.audiobookshelf.native.preview.downloads"
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var error: String?
    @Published private var fractions: [String: Double] = [:]
    @Published var presented = false
    @Published var cellular = UserDefaults.standard.bool(forKey: "previewDownloadCellular") {
        didSet { UserDefaults.standard.set(cellular, forKey: "previewDownloadCellular"); applyCellularPolicy() }
    }
    private let api: APIClient
    private let delegate = DownloadDelegate()
    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var pumping = false
    private var recovered = false
    private var writable = true
    private var manifest: URL { Self.directory.appendingPathComponent("manifest.json") }
    init(api: APIClient) {
        self.api = api
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            var directory = Self.directory
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            try directory.setResourceValues(resource)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            if FileManager.default.fileExists(atPath: manifest.path) {
                let saved = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
                guard saved.version == 1, Set(saved.entries.map(\.id)).count == saved.entries.count,
                      saved.entries.allSatisfy({ entry in
                          UUID(uuidString: entry.id) != nil && UUID(uuidString: entry.generation) != nil && !entry.tracks.isEmpty &&
                          entry.media.duration.isFinite && entry.media.duration > 0 &&
                          Set(entry.finished).count == entry.finished.count && entry.finished.allSatisfy(entry.tracks.indices.contains) &&
                          (entry.state != .ready || entry.finished.count == entry.tracks.count)
                      }) else { throw ListeningJournal.Failure.invalidData }
                entries = saved.entries
                var recovered = entries
                for index in recovered.indices {
                    let valid = recovered[index].finished.filter { part in
                        let file = localFile(recovered[index], part)
                        return ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
                    }
                    if valid.count != recovered[index].finished.count {
                        recovered[index].finished = valid; recovered[index].state = .failed
                        recovered[index].error = "A downloaded file is missing. Retry to restore it; existing files are retained."
                    }
                }
                if recovered.map(\.finished) != entries.map(\.finished) { try save(recovered) }
            }
            for file in try FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("staging-") {
                try? FileManager.default.removeItem(at: file)
            }
        } catch { self.error = "Downloads could not be restored: " + error.localizedDescription; writable = false }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        config.allowsCellularAccess = true; config.httpMaximumConnectionsPerHost = 2
        delegate.owner = self
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: OperationQueue.main)
        session.getAllTasks { [weak self] existing in
            Task { @MainActor in
                guard let self else { return }
                for task in existing {
                    guard let task = task as? URLSessionDownloadTask, task.state != .completed, task.state != .canceling, let key = task.taskDescription, let (entry, index) = self.part(for: key), !self.entries[entry].finished.contains(index) else { task.cancel(); continue }
                    self.tasks[key] = task
                }
                self.recovered = true
                self.refresh()
            }
        }
    }
    var account: AccountIdentity? {
        guard let credentials = api.credentials, let id = credentials.userID else { return nil }
        return try? AccountIdentity(server: credentials.server, userID: id)
    }
    var visible: [Entry] { entries.filter { $0.account == account } }
    private func applyCellularPolicy() {
        do {
            var next = entries
            for index in next.indices where next[index].state == .queued { next[index].generation = UUID().uuidString }
            try save(next)
            for task in tasks.values { task.cancel() }
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    func fraction(for entry: Entry) -> Double {
        let partial = entry.tracks.indices.filter { !entry.finished.contains($0) }.reduce(0.0) { $0 + (fractions[key(entry, $1)] ?? 0) }
        return min(max((Double(entry.finished.count) + partial) / Double(entry.tracks.count), 0), 1)
    }
    func refresh() { Task { await pump() } }
    private func save(_ values: [Entry]) throws {
        guard writable else { throw ListeningJournal.Failure.invalidData }
        try JSONEncoder().encode(Manifest(version: 1, entries: values)).write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries = values
    }
    func enqueue(item: LibraryItem, episode: Episode?) async {
        do {
            let identity = try await api.currentAccount()
            let user = try await api.me()
            guard account == identity else { throw CancellationError() }
            guard user.permissions.download == true else { throw APIError.http(403) }
            let detail = try await api.item(id: item.id)
            guard account == identity else { throw CancellationError() }
            let selected = episode.flatMap { old in detail.media.episodes?.first { $0.id == old.id } } ?? episode
            let tracks = selected.map { $0.audioTrack.map { [$0] } ?? [] } ?? detail.media.tracks ?? []
            guard !tracks.isEmpty, tracks.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.startOffset.isFinite && $0.startOffset >= 0 }) else { throw APIError.noAudio }
            for track in tracks { _ = try downloadURL(track, account: identity, itemID: item.id) }
            if entries.contains(where: { $0.account == identity && $0.media.libraryItemID == item.id && $0.media.episodeID == episode?.id }) { presented = true; return }
            let progress = user.mediaProgress.first { $0.libraryItemId == item.id && $0.episodeId == episode?.id }
            let duration = tracks.map { $0.startOffset + $0.duration }.max()!
            let media = ListeningMedia(itemID: item.id, episodeID: episode?.id, title: selected?.title ?? item.title, author: item.author, mediaType: item.mediaType, duration: duration, startTime: progress?.currentTime ?? 0)
            let entry = Entry(id: UUID().uuidString, account: identity, media: media, tracks: tracks, chapters: selected?.chapters ?? detail.media.chapters ?? [], serverPosition: progress?.currentTime ?? 0, serverUpdatedAt: progress?.lastUpdate ?? 0, generation: UUID().uuidString, finished: [], state: .queued, error: nil)
            try FileManager.default.createDirectory(at: Self.directory.appendingPathComponent(entry.id), withIntermediateDirectories: true)
            try save(entries + [entry])
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func downloadURL(_ track: AudioTrack, account: AccountIdentity, itemID: String) throws -> URL {
        let path = track.contentUrl
        let prefix = "/api/items/" + itemID + "/file/"
        guard path.hasPrefix(prefix), !path.contains("?"), !path.contains("#") else { throw APIError.unsafeMediaURL }
        let fileID = String(path.dropFirst(prefix.count))
        guard !fileID.isEmpty, !fileID.contains("/"), !fileID.contains("..") else { throw APIError.unsafeMediaURL }
        return try ServerAddress(account.server).url(path: path + "/download")
    }
    private func localFile(_ entry: Entry, _ index: Int) -> URL {
        let track = entry.tracks[index]
        let known: [String: String] = ["audio/wav": "wav", "audio/x-wav": "wav", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/flac": "flac", "audio/ogg": "ogg"]
        let raw = track.metadata?.ext ?? track.metadata?.filename.map { URL(fileURLWithPath: $0).pathExtension } ?? known[track.mimeType ?? ""] ?? "m4b"
        let ext = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let safe = !ext.isEmpty && ext.count <= 10 && ext.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) ? ext : "m4b"
        return Self.directory.appendingPathComponent(entry.id).appendingPathComponent("audio-\(index)." + safe)
    }
    private func key(_ entry: Entry, _ index: Int) -> String { entry.id + ":" + entry.generation + ":" + String(index) }
    private func part(for key: String) -> (Int, Int)? {
        let parts = key.split(separator: ":")
        guard parts.count == 3, let index = Int(parts[2]), let entry = entries.firstIndex(where: { $0.id == parts[0] && $0.generation == parts[1] }), entries[entry].tracks.indices.contains(index), entries[entry].state == .queued else { return nil }
        return (entry, index)
    }
    private func pump() async {
        guard recovered, !pumping, writable else { return }
        pumping = true; defer { pumping = false }
        do {
            guard let identity = account else { return }
            let token = try await api.validToken()
            guard identity == account else { return }
            for entry in entries where entry.account == identity && entry.state == .queued {
                for index in entry.tracks.indices where !entry.finished.contains(index) {
                    let key = key(entry, index)
                    guard tasks[key] == nil else { continue }
                    if tasks.count >= 2 { return }
                    var request = URLRequest(url: try downloadURL(entry.tracks[index], account: identity, itemID: entry.media.libraryItemID))
                    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    request.allowsCellularAccess = cellular
                    let task = session.downloadTask(with: request); task.taskDescription = key
                    tasks[key] = task; task.resume()
                }
            }
        } catch { self.error = "Downloads are waiting: " + error.localizedDescription }
    }
    fileprivate func progress(task: URLSessionDownloadTask, received: Int64, expected: Int64) {
        guard let key = task.taskDescription, part(for: key) != nil, expected > 0 else { return }
        fractions[key] = min(max(Double(received) / Double(expected), 0), 1)
    }
    fileprivate func completed(task: URLSessionTask, file: URL?, error: Error?) {
        defer { if let file { try? FileManager.default.removeItem(at: file) }; refresh() }
        guard let key = task.taskDescription else { return }
        tasks.removeValue(forKey: key)
        fractions.removeValue(forKey: key)
        guard let (entry, index) = part(for: key) else { return }
        do {
            if let error { throw error }
            guard let response = task.response as? HTTPURLResponse, response.statusCode == 200, let file else { throw APIError.http((task.response as? HTTPURLResponse)?.statusCode ?? 0) }
            let type = response.mimeType?.lowercased() ?? ""
            guard type.hasPrefix("audio/") || type == "application/octet-stream" || type == "video/mp4" else { throw Failure.invalidAudio }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, response.expectedContentLength < 0 || response.expectedContentLength == size else { throw ListeningJournal.Failure.invalidData }
            let target = localFile(entries[entry], index)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: file, to: target)
            var next = entries
            if !next[entry].finished.contains(index) { next[entry].finished.append(index) }
            if next[entry].finished.count == next[entry].tracks.count { next[entry].state = .ready }
            try save(next)
        } catch {
            var next = entries; next[entry].state = .failed; next[entry].error = error.localizedDescription
            do { try save(next) } catch { self.error = error.localizedDescription }
            for (key, other) in tasks where key.hasPrefix(next[entry].id + ":") { other.cancel() }
        }
    }
    func cancel(_ entry: Entry) {
        do {
            var next = entries
            guard let index = next.firstIndex(where: { $0.id == entry.id && $0.account == account }) else { return }
            let old = next[index].generation; next[index].generation = UUID().uuidString; next[index].state = .cancelled
            try save(next)
            for (key, task) in tasks where key.hasPrefix(entry.id + ":" + old + ":") { task.cancel() }
        } catch { self.error = error.localizedDescription }
    }
    func retry(_ entry: Entry) {
        do {
            var next = entries
            guard let index = next.firstIndex(where: { $0.id == entry.id && $0.account == account }) else { return }
            next[index].generation = UUID().uuidString; next[index].state = .queued; next[index].error = nil
            try save(next); refresh()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ entry: Entry, player: ApplePlayback) async {
        do {
            guard entry.account == account else { throw APIError.signInRequired }
            if player.offlineID == entry.id { try await player.stop() }
            cancel(entry)
            guard entries.first(where: { $0.id == entry.id })?.state != .queued else { return }
            try save(entries.filter { $0.id != entry.id })
            try FileManager.default.removeItem(at: Self.directory.appendingPathComponent(entry.id))
        } catch { self.error = error.localizedDescription }
    }
    func audio(_ entry: Entry) throws -> OfflineAudio {
        guard entry.account == account, entry.state == .ready else { throw APIError.signInRequired }
        let files = entry.tracks.indices.map { localFile(entry, $0) }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw ListeningJournal.Failure.invalidData }
        return OfflineAudio(id: entry.id, account: entry.account, media: entry.media, files: files, tracks: entry.tracks, chapters: entry.chapters, serverPosition: entry.serverPosition, serverUpdatedAt: entry.serverUpdatedAt)
    }
}
