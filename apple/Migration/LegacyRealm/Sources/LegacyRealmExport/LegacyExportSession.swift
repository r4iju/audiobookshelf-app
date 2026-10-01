import Foundation

public enum LegacyExportSessionError: Error, Equatable {
    case busy
    case nothingToSave
    case saveUnavailable
}

/// Writes and removes the export package; `LegacyExportJob` in the app.
public protocol LegacyExportPackaging: AnyObject {
    func run(webStorage: [String: String], copyRealm: (URL) throws -> Void, progress: ((LegacyExportProgress) -> Void)?) throws -> LegacyExportResult
    func discard() throws
}

extension LegacyExportJob: LegacyExportPackaging {}

/// The export and save lifecycle of the legacy app's export action. While a save dialog holds the
/// package, nothing may replace or remove it, and every save resolves exactly once, so a dialog
/// that never appeared cannot block later saves. Safe to call from any thread.
public final class LegacyExportSession {
    public typealias SaveCompletion = (Result<Bool, LegacyExportSessionError>) -> Void
    /// Shows the save dialog for the package and reports, once, how it ended; a dialog that cannot
    /// be shown reports `.failure(.saveUnavailable)`.
    public typealias Presenter = (URL, @escaping SaveCompletion) -> Void

    private enum State {
        case idle
        case exporting
        case ready(LegacyExportResult)
        case saving(LegacyExportResult, UUID)
    }

    private let job: LegacyExportPackaging
    private let lock = NSLock()
    private var state = State.idle

    public init(job: LegacyExportPackaging) {
        self.job = job
    }

    public func export(webStorage: [String: String], copyRealm: (URL) throws -> Void, progress: ((LegacyExportProgress) -> Void)?) throws -> LegacyExportResult {
        try transition { state in
            switch state {
            case .exporting, .saving: throw LegacyExportSessionError.busy
            case .idle, .ready: state = .exporting
            }
        }
        do {
            let result = try job.run(webStorage: webStorage, copyRealm: copyRealm, progress: progress)
            transition { $0 = .ready(result) }
            return result
        } catch {
            transition { $0 = .idle }
            throw error
        }
    }

    public func save(presentingWith present: Presenter, completion: @escaping SaveCompletion) {
        let token = UUID()
        let url: URL
        do {
            url = try transition { state -> URL in
                switch state {
                case .idle: throw LegacyExportSessionError.nothingToSave
                case .exporting, .saving: throw LegacyExportSessionError.busy
                case let .ready(result):
                    state = .saving(result, token)
                    return result.url
                }
            }
        } catch {
            return completion(.failure(error as? LegacyExportSessionError ?? .saveUnavailable))
        }
        present(url) { outcome in
            let current = self.transition { state -> Bool in
                guard case let .saving(result, active) = state, active == token else { return false }
                state = .ready(result)
                return true
            }
            if current { completion(outcome) }
        }
    }

    public func discard() throws {
        try transition { state in
            switch state {
            case .exporting, .saving: throw LegacyExportSessionError.busy
            case .idle, .ready: state = .idle
            }
        }
        try job.discard()
    }

    private func transition<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
