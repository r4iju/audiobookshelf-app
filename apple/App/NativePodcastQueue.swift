import Foundation
import Combine
import CryptoKit

@MainActor final class NativePodcastQueue: ObservableObject {
    enum State: String, Codable { case pending, failed }
    struct Record: Codable, Identifiable, Equatable {
        let id: UUID
        let account: AccountIdentity
        let itemID: String
        let enclosureID: String
        var title: String
        var state: State
        var failedJobIDs: [String]?
        var key: Key { Key(account: account, itemID: itemID, enclosureID: enclosureID) }
    }
    struct Key: Hashable { let account: AccountIdentity; let itemID: String; let enclosureID: String }
    private struct Manifest: Codable { let version: Int; let records: [Record] }
    static var file: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativePodcastQueue/requests.json") }
    @Published private(set) var revision = 0
    @Published private var storageError: String?
    @Published private var authenticationError: String?
    var error: String? { storageError ?? authenticationError }
    private struct Receipt { let owner: AccountIdentity; let itemID: String; let job: PodcastDownload }
    private var unsavedReceipts: [String: Receipt] = [:]
    var hasUnsavedResults: Bool { unsavedReceipts.values.contains { $0.owner == account } }
    private var records: [Record] = []
    private var writable = true
    private let api: APIClient
    private var events: ServerEvents?
    private var connectionTask: Task<Void, Never>?
    private var connectedAccount: AccountIdentity?
    private var generation = UUID()
    private var account: AccountIdentity? {
        guard let credentials = api.credentials, let user = credentials.userID else { return nil }
        return try? AccountIdentity(server: credentials.server, userID: user)
    }
    init(api: APIClient) {
        self.api = api
        do {
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: Self.file.path) {
                let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.file))
                guard manifest.version == 1, Set(manifest.records.map(\.id)).count == manifest.records.count,
                      Set(manifest.records.map(\.key)).count == manifest.records.count,
                      manifest.records.allSatisfy({ !$0.itemID.isEmpty && $0.enclosureID.count == 64 && $0.enclosureID.allSatisfy { $0.isHexDigit } }) else { throw ListeningJournal.Failure.invalidData }
                records = manifest.records
            }
        } catch { writable = false; storageError = NativeStrings.current("Server download requests could not be restored. The original data is retained. {0}", error.localizedDescription) }
    }
    func connect() {
        guard account != connectedAccount || connectionTask == nil else { return }
        generation = UUID(); let request = generation
        connectionTask?.cancel(); events?.stop(); events = nil; connectionTask = nil
        connectedAccount = account; authenticationError = nil; revision += 1
        guard let owner = account else { return }
        let stream = ServerEvents(api: api); events = stream
        connectionTask = Task {
            await stream.listen(account: owner, onEvent: { event in
                guard generation == request, account == owner else { return }
                if event.name == "init" { authenticationError = nil; retrySavingResults(); revision += 1 }
                else if event.name == "episode_download_finished", let job = try? JSONDecoder().decode(PodcastDownload.self, from: event.data), let itemID = job.libraryItemId {
                    do {
                        if job.failed { try receiveFailure(itemID: itemID, job: job) }
                        revision += 1
                    } catch { storageError = NativeStrings.current("The server download result could not be saved: {0}", error.localizedDescription) }
                }
            }, onFailure: { failure in
                guard generation == request, account == owner else { return }
                if failure as? APIError == .signInRequired { authenticationError = ConnectionStore.recovery(for: failure) }
            })
            if generation == request { events = nil; connectionTask = nil }
        }
    }
    func pending(itemID: String) -> Set<String> {
        Set(records.filter { $0.account == account && $0.itemID == itemID && $0.state == .pending }.map(\.enclosureID))
    }
    func failures(itemID: String) -> [Record] { records.filter { $0.account == account && $0.itemID == itemID && $0.state == .failed } }
    func begin(itemID: String, episodes: [PodcastFeedEpisode]) throws {
        guard let account else { throw APIError.signInRequired }
        retrySavingResults()
        guard !hasUnsavedResults else { throw ListeningJournal.Failure.invalidData }
        var next = records
        for episode in episodes {
            guard let url = episode.enclosureURL else { continue }
            let hash = Self.identity(url)
            if let index = next.firstIndex(where: { $0.account == account && $0.itemID == itemID && $0.enclosureID == hash }) {
                next[index].state = .pending; next[index].title = episode.title
            } else { next.append(Record(id: UUID(), account: account, itemID: itemID, enclosureID: hash, title: episode.title, state: .pending)) }
        }
        try save(next)
    }
    func reject(itemID: String, episodes: [PodcastFeedEpisode]) throws {
        let rejected = Set(episodes.compactMap(\.enclosureURL).map(Self.identity))
        var next = records
        for index in next.indices where next[index].account == account && next[index].itemID == itemID && rejected.contains(next[index].enclosureID) { next[index].state = .failed }
        try save(next)
    }
    func receiveFailure(itemID: String, job: PodcastDownload) throws {
        guard let owner = account, let url = job.url else { return }
        let receiptKey = owner.server + "\n" + owner.userID + "\n" + itemID + "\n" + job.id
        guard let index = records.firstIndex(where: { $0.account == owner && $0.itemID == itemID && $0.enclosureID == Self.identity(url) }),
              !(records[index].failedJobIDs ?? []).contains(job.id) else { return }
        var next = records
        next[index].state = .failed
        next[index].failedJobIDs = (next[index].failedJobIDs ?? []) + [job.id]
        do {
            try save(next)
            unsavedReceipts.removeValue(forKey: receiptKey)
            if unsavedReceipts.isEmpty, writable { storageError = nil }
        } catch {
            unsavedReceipts[receiptKey] = Receipt(owner: owner, itemID: itemID, job: job)
            storageError = NativeStrings.current("The server download result could not be saved: {0}", error.localizedDescription)
            throw error
        }
    }
    func retrySavingResults() {
        for receipt in Array(unsavedReceipts.values) where receipt.owner == account {
            do { try receiveFailure(itemID: receipt.itemID, job: receipt.job) } catch { break }
        }
    }
    func reconcile(itemID: String, episodes: [Episode]) throws {
        let available = Set(episodes.compactMap { $0.enclosure?.url }.map(Self.identity))
        try save(records.filter { !($0.account == account && $0.itemID == itemID && available.contains($0.enclosureID)) })
        unsavedReceipts = unsavedReceipts.filter { _, receipt in
            !(receipt.owner == account && receipt.itemID == itemID && receipt.job.url.map { available.contains(Self.identity($0)) } == true)
        }
        if unsavedReceipts.isEmpty, writable { storageError = nil }
    }
    func adoptLegacy(itemID: String) throws {
        guard let account else { throw APIError.signInRequired }
        let key = "previewServerPodcastRequests." + Self.identity(account.server + "\n" + account.userID + "\n" + itemID)
        guard !UserDefaults.standard.bool(forKey: key + ".adopted") else { return }
        var next = records
        let hashes = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard hashes.allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isHexDigit } }) else { throw ListeningJournal.Failure.invalidData }
        for hash in hashes where !next.contains(where: { $0.account == account && $0.itemID == itemID && $0.enclosureID == hash }) {
            next.append(Record(id: UUID(), account: account, itemID: itemID, enclosureID: hash, title: "Podcast episode", state: .pending))
        }
        try save(next)
        UserDefaults.standard.set(true, forKey: key + ".adopted")
    }
    private static func identity(_ url: String) -> String { SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func save(_ next: [Record]) throws {
        guard writable else { throw ListeningJournal.Failure.invalidData }
        guard next != records else { return }
        try JSONEncoder().encode(Manifest(version: 1, records: next)).write(to: Self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = next; revision += 1
    }
}
