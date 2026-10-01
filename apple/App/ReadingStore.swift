import Foundation
import Combine

@MainActor final class ReadingStore: ObservableObject {
    struct Position: Codable {
        let account: AccountIdentity
        let itemID: String
        let format: String
        var fileID: String? = nil
        var location: String
        var fraction: Double
        var updatedAt: Double
        var revision: String
        var pending: Bool
        var rotation: Int
        var serverLocation: String? = nil
        var issuedLocation: String? = nil
        var issuedRevision: String? = nil
    }
    private struct Document: Codable { let version: Int; let positions: [Position] }
    static var file: URL { ListeningSync.file.deletingLastPathComponent().appendingPathComponent("reading.json") }
    @Published private(set) var error: String?
    @Published private(set) var waitingForListening = false
    private let player: ApplePlayback
    private var positions: [Position] = []
    private var writable = true
    private var transfer: Task<Void, Never>?
    private var syncRequested = false
    init(player: ApplePlayback) {
        self.player = player
        do {
            if FileManager.default.fileExists(atPath: Self.file.path) {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Self.file))
                guard document.version == 1, document.positions.allSatisfy({ $0.fraction.isFinite && $0.fraction >= 0 && $0.fraction <= 1 && $0.updatedAt.isFinite }) else { throw ListeningJournal.Failure.invalidData }
                positions = document.positions
            }
        } catch { self.error = "Saved reading could not be restored: " + error.localizedDescription; writable = false }
    }
    func position(account: AccountIdentity, itemID: String, format: String, fileID: String? = nil) -> Position? {
        positions.first { $0.account == account && $0.itemID == itemID && $0.format == format && $0.fileID == fileID }
    }
    func remember(_ position: Position) throws {
        var next = positions
        if let index = next.firstIndex(where: { $0.account == position.account && $0.itemID == position.itemID && $0.format == position.format && $0.fileID == position.fileID }) { next[index] = position }
        else { next.append(position) }
        try save(next)
    }
    func update(account: AccountIdentity, itemID: String, format: String, location: String, fraction: Double, rotation: Int, fileID: String? = nil) throws {
        let old = position(account: account, itemID: itemID, format: format, fileID: fileID)
        if old?.location == location && old?.rotation == rotation && old?.fraction == fraction { return }
        let changed = old?.location != location
        let correctedFraction = old?.fraction != fraction
        try remember(Position(account: account, itemID: itemID, format: format, fileID: fileID, location: location, fraction: fraction,
                              updatedAt: changed ? Date().timeIntervalSince1970 * 1000 : old!.updatedAt,
                              revision: changed || correctedFraction ? UUID().uuidString : old!.revision, pending: fileID == nil && (changed || correctedFraction || old?.pending == true),
                              rotation: rotation, serverLocation: old?.serverLocation, issuedLocation: old?.issuedLocation, issuedRevision: old?.issuedRevision))
    }
    func adopt(_ remote: MediaProgress, account: AccountIdentity, itemID: String, format: String) throws {
        guard writable else { return }
        guard let location = remote.ebookLocation else { return }
        let old = position(account: account, itemID: itemID, format: format)
        let updated = remote.lastUpdate ?? 0
        if var old, old.pending, old.issuedLocation == location, old.issuedRevision != old.revision {
            old.serverLocation = location
            try remember(old)
            return
        }
        if remoteSupersedes(remote, position: old) {
            try remember(Position(account: account, itemID: itemID, format: format, location: location, fraction: remote.ebookProgress ?? 0, updatedAt: updated, revision: UUID().uuidString, pending: false, rotation: old?.rotation ?? 0, serverLocation: location))
        }
    }
    private func remoteSupersedes(_ remote: MediaProgress, position: Position?) -> Bool {
        guard let location = remote.ebookLocation else { return false }
        guard let position else { return true }
        let olderOwnPublication = position.pending && position.issuedLocation == location && position.issuedRevision != position.revision
        return !olderOwnPublication && location != position.serverLocation && (remote.lastUpdate ?? 0) > position.updatedAt
    }
    func reconcile(api: APIClient, account: AccountIdentity, itemID: String, format: String) async {
        guard writable else { return }
        do {
            let user = try await api.me()
            guard try await api.currentAccount() == account else { throw CancellationError() }
            if let remote = user.mediaProgress.first(where: { $0.libraryItemId == itemID && $0.episodeId == nil }) {
                try adopt(remote, account: account, itemID: itemID, format: format)
            }
            sync(api: api)
        } catch { if !(error is CancellationError) { self.error = "Reading is saved on this device and waiting to sync: " + error.localizedDescription } }
    }
    func sync(api: APIClient) {
        guard writable else { return }
        guard transfer == nil else { syncRequested = true; return }
        transfer = Task {
            defer {
                transfer = nil
                if syncRequested { syncRequested = false; sync(api: api) }
            }
            do {
                let account = try await api.currentAccount()
                while let position = positions.first(where: { $0.account == account && $0.pending }) {
                    let user = try await api.me()
                    guard try await api.currentAccount() == account else { throw CancellationError() }
                    guard let current = self.position(account: account, itemID: position.itemID, format: position.format), current.revision == position.revision else { continue }
                    if let remote = user.mediaProgress.first(where: { $0.libraryItemId == position.itemID && $0.episodeId == nil }) {
                        try adopt(remote, account: account, itemID: position.itemID, format: position.format)
                    }
                    guard let reconciled = self.position(account: account, itemID: position.itemID, format: position.format),
                          reconciled.pending, reconciled.revision == position.revision else { continue }
                    guard try await player.publishReading(account: account, itemID: position.itemID, location: position.location, fraction: position.fraction, beforePublication: {
                        guard var issued = self.position(account: account, itemID: position.itemID, format: position.format) else { throw CancellationError() }
                        issued.issuedLocation = position.location; issued.issuedRevision = position.revision
                        try self.remember(issued)
                    }) else {
                        waitingForListening = true
                        return
                    }
                    waitingForListening = false
                    guard try await api.currentAccount() == account else { throw CancellationError() }
                    if var current = self.position(account: account, itemID: position.itemID, format: position.format) {
                        current.serverLocation = position.location
                        if current.revision == position.revision { current.pending = false }
                        if current.issuedRevision == position.revision { current.issuedLocation = nil; current.issuedRevision = nil }
                        try remember(current)
                    }
                }
                error = nil
            } catch { if !(error is CancellationError) { self.error = "Reading is saved on this device and waiting to sync: " + error.localizedDescription } }
        }
    }
    private func save(_ next: [Position]) throws {
        guard writable else { throw ListeningJournal.Failure.invalidData }
        guard next.allSatisfy({ $0.fraction.isFinite && $0.fraction >= 0 && $0.fraction <= 1 }) else { throw ListeningJournal.Failure.invalidData }
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Document(version: 1, positions: next)).write(to: Self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        positions = next
    }
}
