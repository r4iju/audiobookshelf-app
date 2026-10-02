import Foundation

public enum DiagnosticCategory: String, Codable, CaseIterable {
    case connection, server, media, sync, download, reading, podcast
}

public struct DiagnosticEvent: Codable, Equatable, Identifiable {
    public let id: UUID
    public let category: DiagnosticCategory
    public let message: String
    public let detail: String?
    public let firstDate: Date
    public fileprivate(set) var lastDate: Date
    public fileprivate(set) var count: Int

    public init(category: DiagnosticCategory, message: String, detail: String?, date: Date) {
        id = UUID(); self.category = category; self.message = message; self.detail = detail
        firstDate = date; lastDate = date; count = 1
    }
}

/// A bounded on-device record of failures. Text is redacted before it is kept, so the saved file never holds credentials.
public final class DiagnosticLog {
    private struct Document: Codable {
        let version: Int
        let events: [DiagnosticEvent]
    }
    public private(set) var events: [DiagnosticEvent]
    private let file: URL
    private let limit: Int
    private let now: () -> Date

    public init(file: URL, limit: Int = 200, now: @escaping () -> Date = Date.init) {
        self.file = file; self.limit = limit; self.now = now
        let saved = (try? Data(contentsOf: file)).flatMap { try? Self.decoder.decode(Document.self, from: $0) }
        events = saved?.version == 1 ? Array(saved!.events.suffix(limit)) : []
    }

    public func record(_ category: DiagnosticCategory, message: String, detail: String? = nil) throws {
        let message = DiagnosticRedactor.redact(message)
        let detail = detail.map { DiagnosticRedactor.redact($0) }
        var next = events
        if let last = next.last, last.category == category, last.message == message, last.detail == detail {
            next[next.count - 1].count += 1
            next[next.count - 1].lastDate = now()
        } else {
            next.append(DiagnosticEvent(category: category, message: message, detail: detail, date: now()))
        }
        try save(Array(next.suffix(limit)))
    }

    public func clear() throws { try save([]) }

    private func save(_ next: [DiagnosticEvent]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(Document(version: 1, events: next)).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        events = next
    }

    private static let encoder: JSONEncoder = { let value = JSONEncoder(); value.dateEncodingStrategy = .secondsSince1970; return value }()
    private static let decoder: JSONDecoder = { let value = JSONDecoder(); value.dateDecodingStrategy = .secondsSince1970; return value }()
}

extension DiagnosticEvent {
    /// The text a screen shows: credentials were removed when the event was saved; addresses are masked on request.
    public func presented(maskingAddresses: Bool) -> (message: String, detail: String?) {
        (DiagnosticRedactor.redact(message, maskingAddresses: maskingAddresses), detail.map { DiagnosticRedactor.redact($0, maskingAddresses: maskingAddresses) })
    }
}
