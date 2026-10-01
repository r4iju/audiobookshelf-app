import Foundation

/// Progress writes whose server handler may still be running.
///
/// Server 2.30 has no request barrier or idempotency: a handler keeps running after its client gave
/// up (`PlaybackSessionManager.syncLocalSession`, `MeController.createUpdateMediaProgress`), and if
/// it reaches its progress lookup after a reset's delete it creates a new row, bringing the progress
/// back. A local session sync also replaces the session's total and position unconditionally, and
/// may update progress without comparing times, so a late handler can undo anything sent after it.
/// Only an answer to the exact transmission shows that its handler finished; a replay being
/// accepted, a later read of the row or elapsed time show nothing about it. So every transmission
/// is recorded, with the exact body, before it is sent, and removed only once it was answered or
/// certainly never left this device. While one is unresolved, only an identical write for the same
/// media is sent; anything else waits on this device. A server restart ends every handler, so the
/// owner's confirmation of a restart asked for after them resolves them.
@MainActor final class PublicationLedger {
    struct Write: Codable, Equatable {
        let id: UUID
        let account: AccountIdentity
        let itemID: String
        let episodeID: String?
        let method: String
        let path: String
        /// The body exactly as sent. Headers, and with them the token, are not kept.
        let body: Data?
        let issuedAt: Double

        func concerns(_ other: Write) -> Bool { account == other.account && itemID == other.itemID && episodeID == other.episodeID }

        /// Whether `other` sends exactly this again, so whichever handler runs last leaves the same.
        func repeats(_ other: Write) -> Bool {
            guard method == other.method, path == other.path else { return false }
            if body == other.body { return true }
            // Key order of serialized dictionaries differs between launches.
            guard let body, let otherBody = other.body,
                  let value = try? JSONSerialization.jsonObject(with: body) as? NSObject,
                  let otherValue = try? JSONSerialization.jsonObject(with: otherBody) as? NSObject else { return false }
            return value.isEqual(otherValue)
        }
    }

    private struct Document: Codable {
        let version: Int
        var writes: [Write]
        /// When an unreadable record was set aside: any write to any server issued before then is unknown.
        var unreadableBefore: Double?
        /// For each server, when a restart was last asked for and confirmed.
        var restarts: [String: Double]
        /// For each server, the restart the owner was asked for and has not confirmed yet.
        var requests: [String: RestartRequest]?
    }

    private struct RestartRequest: Codable {
        let requestedAt: Double
        /// The writes it resolves: a write issued after the request may reach the server after
        /// it restarted.
        let writes: [UUID]
    }

    enum Failure: LocalizedError {
        case unreadable, waiting, restartNotRequested
        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The record of progress sent to the server could not be read or updated, so nothing more is sent. Keep the app's data and try again."
            case .waiting:
                return "An earlier save of this title's progress got no answer, and the server may still apply it over anything sent after it. Later progress is kept on this device until a restart of the Audiobookshelf server is confirmed."
            case .restartNotRequested:
                return "Ask for the server restart first, restart the Audiobookshelf server, then confirm it."
            }
        }
    }

    private let file: URL
    private var document: Document?

    init(file: URL) {
        self.file = file
        guard FileManager.default.fileExists(atPath: file.path) else {
            document = Document(version: 1, writes: [], unreadableBefore: nil, restarts: [:])
            return
        }
        guard let data = try? Data(contentsOf: file) else { document = nil; return }
        if let saved = try? JSONDecoder().decode(Document.self, from: data), saved.version == 1 {
            document = saved
            return
        }
        // Set aside rather than discarded, and every earlier write counts as unknown.
        let now = Self.now
        let aside = file.deletingLastPathComponent().appendingPathComponent("publications-unreadable-\(Int(now)).json")
        do {
            try FileManager.default.moveItem(at: file, to: aside)
            let fresh = Document(version: 1, writes: [], unreadableBefore: now, restarts: [:])
            try Self.write(fresh, to: file)
            document = fresh
        } catch { document = nil }
    }

    private static var now: Double { Date().timeIntervalSince1970 * 1_000 }

    /// Whether a write for the media may still be applied by its server. Always true while the
    /// record cannot be read.
    func unresolved(account: AccountIdentity, itemID: String, episodeID: String?) -> Bool {
        guard let document else { return true }
        if let unreadable = document.unreadableBefore, (document.restarts[account.server] ?? 0) < unreadable { return true }
        return document.writes.contains { $0.account == account && $0.itemID == itemID && $0.episodeID == episodeID }
    }

    /// Records that the owner is asked to restart the server now. Only the writes unresolved at
    /// this moment, and an unreadable record set aside before it, are resolved by confirming it.
    func requestRestart(server: String) throws {
        guard var next = document else { throw Failure.unreadable }
        let writes = next.writes.filter { $0.account.server == server }.map(\.id)
        next.requests = (next.requests ?? [:]).merging([server: RestartRequest(requestedAt: Self.now, writes: writes)]) { $1 }
        try save(next)
    }

    /// Records the owner's confirmation that the server restarted after the last request, which
    /// ended every handler of a write issued before that request. The time it is confirmed says
    /// nothing about when the restart happened, so later writes stay unresolved.
    func confirmRestart(server: String) throws {
        guard var next = document else { throw Failure.unreadable }
        guard let request = next.requests?[server] else { throw Failure.restartNotRequested }
        next.writes.removeAll { request.writes.contains($0.id) }
        next.restarts[server] = max(next.restarts[server] ?? 0, request.requestedAt)
        next.requests?[server] = nil
        try save(next)
    }

    /// Records each transmission of a write to the media's progress before it is sent, and
    /// resolves it once its outcome shows its handler is not running.
    func issuing(account: AccountIdentity, itemID: String, episodeID: String?) -> APIClient.IssuingHook {
        { request in
            let write = Write(id: UUID(), account: account, itemID: itemID, episodeID: episodeID, method: request.httpMethod ?? "GET",
                              path: request.url?.path ?? "", body: request.httpBody, issuedAt: Self.now)
            try self.issue(write)
            return { error in
                if error.map(Self.settled(by:)) ?? true { try? self.resolve(write.id) }
            }
        }
    }

    /// Records a write about to be sent. Throws, and it must not be sent, when that fails or while
    /// a different write for the media may still be applied: a late handler would replace it.
    func issue(_ write: Write) throws {
        guard var next = document else { throw Failure.unreadable }
        if let unreadable = next.unreadableBefore, (next.restarts[write.account.server] ?? 0) < unreadable { throw Failure.waiting }
        guard next.writes.allSatisfy({ !$0.concerns(write) || $0.repeats(write) }) else { throw Failure.waiting }
        next.writes.append(write)
        try save(next)
    }

    /// Removes a write that was answered, or certainly never sent.
    func resolve(_ id: UUID) throws {
        guard var next = document else { throw Failure.unreadable }
        guard next.writes.contains(where: { $0.id == id }) else { return }
        next.writes.removeAll { $0.id == id }
        try save(next)
    }

    /// A gateway answering for the server says nothing about the server's own handler.
    nonisolated static func settled(byStatus status: Int) -> Bool { ![408, 502, 503, 504].contains(status) }

    /// Whether a failed transmission's handler is certainly not running: something other than a
    /// gateway answered it, or it never left this device. Timeouts, lost connections and
    /// cancellations are unknown.
    nonisolated static func settled(by error: Error) -> Bool {
        if case APIError.http(let status) = error { return settled(byStatus: status) }
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .badURL, .unsupportedURL,
                .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection].contains(error.code)
    }

    private func save(_ next: Document) throws {
        try Self.write(next, to: file)
        document = next
    }

    private static func write(_ document: Document, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS) || os(tvOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(document).write(to: file, options: options)
    }
}
