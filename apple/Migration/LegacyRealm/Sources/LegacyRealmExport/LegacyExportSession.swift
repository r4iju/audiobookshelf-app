import Foundation

public enum LegacyExportSessionError: Error, Equatable {
    case busy
    case nothingToSave
    case saveUnavailable
}

/// The export and save lifecycle of the legacy app's export action.
public final class LegacyExportSession {
    public typealias SaveCompletion = (Result<Bool, LegacyExportSessionError>) -> Void
    /// Shows the save dialog for the package and reports, once, how it ended.
    public typealias Presenter = (URL, @escaping SaveCompletion) -> Void

    private let job: LegacyExportJob
    private var running = false
    private var result: LegacyExportResult?
    private var pending: SaveCompletion?

    public init(job: LegacyExportJob) {
        self.job = job
    }

    public func export(webStorage: [String: String], copyRealm: (URL) throws -> Void, progress: ((LegacyExportProgress) -> Void)?) throws -> LegacyExportResult {
        guard !running else { throw LegacyExportSessionError.busy }
        running = true
        result = nil
        defer { running = false }
        let result = try job.run(webStorage: webStorage, copyRealm: copyRealm, progress: progress)
        self.result = result
        return result
    }

    public func save(presentingWith present: Presenter, completion: @escaping SaveCompletion) {
        guard let url = result?.url, !running else { return completion(.failure(.nothingToSave)) }
        guard pending == nil else { return completion(.failure(.saveUnavailable)) }
        pending = completion
        present(url) { outcome in
            if case let .success(saved) = outcome {
                self.pending?(.success(saved))
                self.pending = nil
            }
        }
    }

    public func discard() throws {
        guard !running else { throw LegacyExportSessionError.busy }
        result = nil
        try job.discard()
    }
}
