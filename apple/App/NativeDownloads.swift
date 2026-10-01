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
        case invalidContent
        var errorDescription: String? { "The server returned unsupported content. Check the server and retry the download." }
    }
    enum State: String, Codable { case queued, ready, failed, cancelled }
    struct Entry: Codable, Identifiable {
        let id: String
        let account: AccountIdentity
        let media: ListeningMedia
        let tracks: [AudioTrack]
        let chapters: [Chapter]
        var ebook: EbookFile?
        var readingProgress: MediaProgress? = nil
        var supplementaryID: String? = nil
        var cellularConsent: Bool? = nil
        var networkPolicy: String? = nil
        var parts: Range<Int> { 0..<(tracks.count + (ebook == nil ? 0 : 1)) }
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
    private var networkObserver: NSObjectProtocol?
    let api: APIClient
    private let delegate = DownloadDelegate()
    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var pumping = false
    private var recovered = false
    private var writable = true
    private var policyBlocked = false
    private var manifest: URL { Self.directory.appendingPathComponent("manifest.json") }
    init(api: APIClient) {
        self.api = api
        networkObserver = NotificationCenter.default.addObserver(forName: AppleNetworkPolicy.changed, object: nil, queue: .main) { [weak self] note in
            guard note.object as? String == AppleNetworkPolicy.downloadsKey else { return }
            Task { @MainActor in self?.applyCellularPolicy() }
        }
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
                          UUID(uuidString: entry.id) != nil && UUID(uuidString: entry.generation) != nil && !entry.parts.isEmpty &&
                          entry.media.duration.isFinite && entry.media.duration >= 0 &&
                          Set(entry.finished).count == entry.finished.count && entry.finished.allSatisfy(entry.parts.contains) &&
                          (entry.state != .ready || entry.finished.count == entry.parts.count)
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
                let policy = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey).rawValue
                for index in recovered.indices where recovered[index].state == .queued && recovered[index].networkPolicy != policy {
                    recovered[index].generation = UUID().uuidString
                    recovered[index].cellularConsent = nil
                    recovered[index].networkPolicy = policy
                }
                if recovered.map(\.finished) != entries.map(\.finished) || recovered.map(\.generation) != entries.map(\.generation) { try save(recovered) }
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
                guard self.writable else { existing.forEach { $0.cancel() }; return }
                var changedEntries = Set<String>()
                var candidates: [(String, URLSessionDownloadTask)] = []
                for task in existing {
                    guard let task = task as? URLSessionDownloadTask, task.state != .completed, task.state != .canceling, let key = task.taskDescription, let (entry, index) = self.part(for: key), !self.entries[entry].finished.contains(index) else { task.cancel(); continue }
                    if task.originalRequest?.allowsCellularAccess != self.allowsCellular(self.entries[entry]) {
                        task.cancel()
                        changedEntries.insert(self.entries[entry].id)
                    }
                    candidates.append((key, task))
                }
                if !changedEntries.isEmpty {
                    self.policyBlocked = true
                    for (key, task) in candidates where changedEntries.contains(String(key.split(separator: ":")[0])) { task.cancel() }
                    do {
                        var next = self.entries
                        for index in next.indices where changedEntries.contains(next[index].id) { next[index].generation = UUID().uuidString }
                        try self.save(next)
                        self.policyBlocked = false
                    } catch {
                        existing.forEach { $0.cancel() }
                        self.error = "Downloads could not restore network permissions: " + error.localizedDescription
                        return
                    }
                }
                for (key, task) in candidates where !changedEntries.contains(String(key.split(separator: ":")[0])) { self.tasks[key] = task }
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
        policyBlocked = true
        for task in tasks.values { task.cancel() }
        do {
            var next = entries
            for index in next.indices where next[index].state == .queued { next[index].generation = UUID().uuidString; next[index].cellularConsent = nil; next[index].networkPolicy = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey).rawValue }
            try save(next)
            policyBlocked = false
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    func fraction(for entry: Entry) -> Double {
        let partial = entry.parts.filter { !entry.finished.contains($0) }.reduce(0.0) { $0 + (fractions[key(entry, $1)] ?? 0) }
        return min(max((Double(entry.finished.count) + partial) / Double(entry.parts.count), 0), 1)
    }
    func refresh() { Task { await pump() } }
    private func save(_ values: [Entry]) throws {
        guard writable else { throw ListeningJournal.Failure.invalidData }
        try JSONEncoder().encode(Manifest(version: 1, entries: values)).write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries = values
    }
    func enqueue(item: LibraryItem, episode: Episode?, supplementaryID: String? = nil) async {
        do {
            let identity = try await api.currentAccount()
            let policy = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey)
            let consent = await AppleNetworkPolicy.request(AppleNetworkPolicy.downloadsKey, title: "this download")
            guard account == identity, policy == AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey) else { throw CancellationError() }
            let user = try await api.me()
            guard account == identity else { throw CancellationError() }
            guard user.permissions.download == true else { throw APIError.http(403) }
            let detail = try await api.item(id: item.id)
            guard account == identity else { throw CancellationError() }
            let selected = episode.flatMap { old in detail.media.episodes?.first { $0.id == old.id } } ?? episode
            let attachment = supplementaryID.flatMap { id in detail.supplementaryEbooks.first { $0.ino == id }?.ebook }
            guard supplementaryID == nil || attachment != nil else { throw APIError.http(404) }
            let tracks = supplementaryID == nil ? (selected.map { $0.audioTrack.map { [$0] } ?? [] } ?? detail.media.tracks ?? []) : []
            let ebook = supplementaryID == nil ? (selected == nil ? detail.media.ebookFile : nil) : attachment
            let progress = supplementaryID == nil ? user.mediaProgress.first { $0.libraryItemId == item.id && $0.episodeId == episode?.id } : nil
            guard !tracks.isEmpty || ebook != nil else { throw APIError.noAudio }
            guard tracks.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.startOffset.isFinite && $0.startOffset >= 0 }) else { throw APIError.noAudio }
            for track in tracks { _ = try downloadURL(track, account: identity, itemID: item.id) }
            if let index = entries.firstIndex(where: { $0.account == identity && $0.media.libraryItemID == item.id && $0.media.episodeID == episode?.id && $0.supplementaryID == supplementaryID }) {
                if entries[index].ebook == nil, let ebook {
                    _ = try downloadURL(path: "/api/items/" + item.id + "/file/" + ebook.ino, account: identity, itemID: item.id)
                    var next = entries
                    let oldGeneration = next[index].generation
                    policyBlocked = true
                    for (key, task) in tasks where key.hasPrefix(next[index].id + ":" + oldGeneration + ":") { task.cancel() }
                    next[index].ebook = ebook; next[index].generation = UUID().uuidString
                    next[index].readingProgress = progress
                    next[index].state = .queued; next[index].error = nil; next[index].cellularConsent = policy == .ask ? consent : nil; next[index].networkPolicy = policy.rawValue
                    try save(next)
                    policyBlocked = false
                    refresh()
                }
                if entries[index].state != .ready {
                    var next = entries
                    let oldGeneration = next[index].generation
                    policyBlocked = true
                    for (key, task) in tasks where key.hasPrefix(next[index].id + ":" + oldGeneration + ":") { task.cancel() }
                    next[index].generation = UUID().uuidString
                    next[index].cellularConsent = policy == .ask ? consent : nil; next[index].networkPolicy = policy.rawValue
                    try save(next)
                    policyBlocked = false
                    refresh()
                }
                presented = true
                return
            }
            if let ebook { _ = try downloadURL(path: "/api/items/" + item.id + "/file/" + ebook.ino, account: identity, itemID: item.id) }
            let duration = tracks.map { $0.startOffset + $0.duration }.max() ?? 0
            let media = ListeningMedia(itemID: item.id, episodeID: episode?.id, title: attachment?.metadata?.filename ?? selected?.title ?? item.title, author: item.author, mediaType: item.mediaType, duration: duration, startTime: progress?.currentTime ?? 0)
            let entry = Entry(id: UUID().uuidString, account: identity, media: media, tracks: tracks, chapters: supplementaryID == nil ? (selected?.chapters ?? detail.media.chapters ?? []) : [], ebook: ebook, readingProgress: progress, supplementaryID: supplementaryID, cellularConsent: policy == .ask ? consent : nil, networkPolicy: policy.rawValue, serverPosition: progress?.currentTime ?? 0, serverUpdatedAt: progress?.lastUpdate ?? 0, generation: UUID().uuidString, finished: [], state: .queued, error: nil)
            try FileManager.default.createDirectory(at: Self.directory.appendingPathComponent(entry.id), withIntermediateDirectories: true)
            try save(entries + [entry])
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func downloadURL(_ track: AudioTrack, account: AccountIdentity, itemID: String) throws -> URL {
        return try downloadURL(path: track.contentUrl, account: account, itemID: itemID)
    }
    private func downloadURL(path: String, account: AccountIdentity, itemID: String) throws -> URL {
        let prefix = "/api/items/" + itemID + "/file/"
        guard path.hasPrefix(prefix), !path.contains("?"), !path.contains("#") else { throw APIError.unsafeMediaURL }
        let fileID = String(path.dropFirst(prefix.count))
        guard !fileID.isEmpty, !fileID.contains("/"), !fileID.contains("..") else { throw APIError.unsafeMediaURL }
        return try ServerAddress(account.server).url(path: path + "/download")
    }
    private func localFile(_ entry: Entry, _ index: Int) -> URL {
        if index == entry.tracks.count, let ebook = entry.ebook {
            let ext = ebook.format.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let safe = !ext.isEmpty && ext.count <= 10 && ext.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) ? ext : "ebook"
            return Self.directory.appendingPathComponent(entry.id).appendingPathComponent("ebook." + safe)
        }
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
        guard parts.count == 3, let index = Int(parts[2]), let entry = entries.firstIndex(where: { $0.id == parts[0] && $0.generation == parts[1] }), entries[entry].parts.contains(index), entries[entry].state == .queued else { return nil }
        return (entry, index)
    }
    private func allowsCellular(_ entry: Entry) -> Bool {
        switch AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey) {
        case .always: return true
        case .never: return false
        case .ask: return entry.cellularConsent == true
        }
    }
    private func pump() async {
        guard recovered, !pumping, writable, !policyBlocked else { return }
        pumping = true; defer { pumping = false }
        do {
            guard let identity = account else { return }
            let token = try await api.validToken()
            guard identity == account, !policyBlocked else { return }
            for entry in entries where entry.account == identity && entry.state == .queued {
                for index in entry.parts where !entry.finished.contains(index) {
                    let key = key(entry, index)
                    guard tasks[key] == nil else { continue }
                    if tasks.count >= 2 { return }
                    let path = index < entry.tracks.count ? entry.tracks[index].contentUrl : "/api/items/" + entry.media.libraryItemID + "/file/" + entry.ebook!.ino
                    var request = URLRequest(url: try downloadURL(path: path, account: identity, itemID: entry.media.libraryItemID))
                    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    request.allowsCellularAccess = allowsCellular(entry)
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
            let ebook = index == entries[entry].tracks.count && entries[entry].ebook != nil
            let valid = ebook ? ["application/pdf", "application/epub+zip", "application/zip", "application/vnd.amazon.ebook", "application/x-mobipocket-ebook", "application/x-cbz", "application/x-cbr", "application/x-rar-compressed"].contains(type) : type.hasPrefix("audio/") || type == "video/mp4"
            guard valid || type == "application/octet-stream" else { throw Failure.invalidContent }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, response.expectedContentLength < 0 || response.expectedContentLength == size else { throw ListeningJournal.Failure.invalidData }
            let target = localFile(entries[entry], index)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: file, to: target)
            var next = entries
            if !next[entry].finished.contains(index) { next[entry].finished.append(index) }
            if next[entry].finished.count == next[entry].parts.count { next[entry].state = .ready }
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
    func retry(_ entry: Entry) async {
        let identity = account
        let policy = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey)
        let consent = await AppleNetworkPolicy.request(AppleNetworkPolicy.downloadsKey, title: "this download")
        guard identity == account, policy == AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey) else { return }
        do {
            var next = entries
            guard let index = next.firstIndex(where: { $0.id == entry.id && $0.account == account }) else { return }
            let oldGeneration = next[index].generation
            policyBlocked = true
            for (key, task) in tasks where key.hasPrefix(entry.id + ":" + oldGeneration + ":") { task.cancel() }
            next[index].generation = UUID().uuidString; next[index].state = .queued; next[index].error = nil; next[index].cellularConsent = policy == .ask ? consent : nil; next[index].networkPolicy = policy.rawValue
            try save(next); policyBlocked = false; refresh()
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
    func ebookURL(_ entry: Entry) throws -> URL {
        guard entry.account == account, entry.state == .ready, entry.ebook != nil else { throw APIError.signInRequired }
        let file = localFile(entry, entry.tracks.count)
        guard FileManager.default.fileExists(atPath: file.path) else { throw ListeningJournal.Failure.invalidData }
        return file
    }
    func audio(_ entry: Entry, progress: MediaProgress? = nil) throws -> OfflineAudio {
        guard entry.account == account, entry.state == .ready else { throw APIError.signInRequired }
        let files = entry.tracks.indices.map { localFile(entry, $0) }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw ListeningJournal.Failure.invalidData }
        let latest = progress.flatMap { value in
            value.libraryItemId == entry.media.libraryItemID && value.episodeId == entry.media.episodeID && (value.lastUpdate ?? 0) >= entry.serverUpdatedAt ? value : nil
        }
        return OfflineAudio(id: entry.id, account: entry.account, media: entry.media, files: files, tracks: entry.tracks, chapters: entry.chapters, serverPosition: latest?.currentTime ?? entry.serverPosition, serverUpdatedAt: latest?.lastUpdate ?? entry.serverUpdatedAt)
    }
}
