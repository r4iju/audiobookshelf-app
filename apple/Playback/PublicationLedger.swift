import Foundation

/// Progress writes whose server handler may still be running.
///
/// Server 2.30 has no request barrier or idempotency: a handler keeps running after its client gave
/// up (`PlaybackSessionManager.syncLocalSession`, `MeController.createUpdateMediaProgress`), and if
/// it reaches its progress lookup after a reset's delete it creates a new row, bringing the progress
/// back. Only an answer to the exact request shows that its handler finished; a replay being
/// accepted, a later read of the row or elapsed time show nothing about it. So every write is
/// recorded, with the exact body, before it is sent, and removed only once it was answered or
/// certainly never left this device. A server restart ends every handler, so the owner's
/// confirmation of one resolves the writes issued to that server before it.
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
    }

    private struct Document: Codable {
        let version: Int
        var writes: [Write]
        /// When an unreadable record was set aside: any write to any server issued before then is unknown.
        var unreadableBefore: Double?
        /// When the owner confirmed that each server restarted.
        var restarts: [String: Double]
    }

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "The record of progress sent to the server could not be read or updated, so nothing more is sent. Keep the app's data and try again."
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

    /// Records the owner's confirmation that the account's server restarted, which ends every
    /// handler of a write issued before it.
    func confirmRestart(server: String) throws {
        guard var next = document else { throw Failure.unreadable }
        let now = Self.now
        next.restarts[server] = now
        next.writes.removeAll { $0.account.server == server && $0.issuedAt < now }
        try save(next)
    }

    /// Sends one write for the media through `send`, which must call `issuing` right before each
    /// transmission. A transmission that cannot be recorded is not sent. The write stays recorded
    /// unless it was answered by the server itself or certainly never left this device.
    func deliver<T>(account: AccountIdentity, itemID: String, episodeID: String?,
                    _ send: (_ issuing: @escaping APIClient.IssuingHook) async throws -> T) async throws -> T {
        let id = UUID()
        var issued = false
        let issuing: APIClient.IssuingHook = { request in
            try self.issue(Write(id: id, account: account, itemID: itemID, episodeID: episodeID, method: request.httpMethod ?? "GET",
                                 path: request.url?.path ?? "", body: request.httpBody, issuedAt: Self.now))
            issued = true
        }
        do {
            let value = try await send(issuing)
            if issued { try? resolve(id) }
            return value
        } catch {
            if issued, Self.settled(by: error) { try? resolve(id) }
            throw error
        }
    }

    /// Records a write about to be sent; throws, and it must not be sent, when that fails.
    func issue(_ write: Write) throws {
        guard var next = document else { throw Failure.unreadable }
        next.writes.removeAll { $0.id == write.id }
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

    /// Whether a failed request's handler is certainly not running: something other than a
    /// gateway answered it, or it never left this device. Timeouts, lost connections and
    /// cancellations are unknown.
    nonisolated static func settled(by error: Error) -> Bool {
        // `APIClient` throws these only before sending or after an answer.
        if error is CancellationError || error is DecodingError { return true }
        if let error = error as? APIError {
            if case .http(let status) = error { return settled(byStatus: status) }
            return true
        }
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
