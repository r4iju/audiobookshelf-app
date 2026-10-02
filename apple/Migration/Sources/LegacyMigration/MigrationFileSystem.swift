import Foundation

/// The file operations whose failure or interruption a migration must survive.
public protocol MigrationFileSystem {
    /// Hard-links `source` at `destination` (same volume, no extra space, legacy file untouched).
    func link(_ source: URL, to destination: URL) throws
    func copy(_ source: URL, to destination: URL) throws
    func availableCapacity(at directory: URL) throws -> Int64
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Reads the next chunk of the file at `url` through `handle`; empty at its end.
    func read(_ handle: FileHandle, upToCount count: Int, of url: URL) throws -> Data
}

public struct LocalMigrationFileSystem: MigrationFileSystem {
    public init() {}

    public func link(_ source: URL, to destination: URL) throws {
        try FileManager.default.linkItem(at: source, to: destination)
    }

    public func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func availableCapacity(at directory: URL) throws -> Int64 {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return Int64(values.volumeAvailableCapacity ?? 0)
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    public func read(_ handle: FileHandle, upToCount count: Int, of url: URL) throws -> Data {
        handle.readData(ofLength: count)
    }
}
