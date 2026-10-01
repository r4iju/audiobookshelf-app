import Foundation

/// Credential-free export of a legacy installation that can cross the sandbox boundary through the
/// Files app: a directory holding `files/<legacy path digest>/<file name>` and `archive.json`. The archive is built
/// under `<name>.partial` and renamed only after `archive.json` (written last) is complete, so a
/// directory without `archive.json` is always an interrupted export.
public struct LegacyArchiveProgress: Equatable {
    public var completedFiles: Int
    public var totalFiles: Int
    public var completedBytes: Int64
    public var totalBytes: Int64
}

public enum LegacyArchive {
    public static let manifestName = "archive.json"
    public static let formatVersion = 1

    private struct Manifest: Codable {
        var formatVersion: Int
        var snapshot: LegacySnapshot
        var digests: [String: String]
        var storedPaths: [String: String]
    }

    @discardableResult
    public static func write(_ snapshot: LegacySnapshot, documents: URL, to destination: URL, progress: ((LegacyArchiveProgress) -> Void)? = nil) throws -> URL {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let partial = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".partial")
        try? FileManager.default.removeItem(at: partial)
        let files = partial.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        var exported = snapshot
        exported.preferences = LegacyStorageAllowlist.archivePreferences(snapshot.preferences)
        exported.webStorage = LegacyStorageAllowlist.archiveWebStorage(snapshot.webStorage)

        // Reuse the migration's path validation so the archive never contains anything a migration
        // from Documents would refuse to read.
        let plan = MigrationPlan(source: LegacySource(kind: .inPlace, snapshot: exported, filesRoot: documents))
        var unique: [String: PlannedFile] = [:]
        for planned in plan.files.values { unique[planned.legacyPath] = planned }
        let ordered = unique.values.sorted { $0.legacyPath < $1.legacyPath }
        var report = LegacyArchiveProgress(completedFiles: 0, totalFiles: ordered.count, completedBytes: 0, totalBytes: ordered.reduce(0) { $0 + $1.size })
        progress?(report)
        var digests: [String: String] = [:]
        var storedPaths: [String: String] = [:]
        for planned in ordered {
            let stored = MigrationPlan.archivedPath(planned.legacyPath)
            storedPaths[planned.legacyPath] = stored
            let target = files.appendingPathComponent(stored)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: planned.source, to: target)
            digests[planned.legacyPath] = try ContainedFile.digest(of: target, reading: LocalMigrationFileSystem()).sha256
            report.completedFiles += 1
            report.completedBytes += planned.size
            progress?(report)
        }

        let manifest = try MigrationJSON.encoder.encode(Manifest(formatVersion: formatVersion, snapshot: exported, digests: digests, storedPaths: storedPaths))
        try manifest.write(to: partial.appendingPathComponent(manifestName), options: .atomic)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    public static func open(_ url: URL) throws -> LegacySource {
        let manifestURL = url.appendingPathComponent(manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw LegacyMigrationError.archiveIncomplete }
        let manifest: Manifest
        do {
            manifest = try MigrationJSON.decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw LegacyMigrationError.archiveUnreadable("The export description could not be read.")
        }
        guard manifest.formatVersion == formatVersion else {
            throw LegacyMigrationError.archiveUnreadable("This export was made by an unsupported version (\(manifest.formatVersion)).")
        }
        return LegacySource(kind: .archive, snapshot: manifest.snapshot, filesRoot: url.appendingPathComponent("files"), recordedDigests: manifest.digests, storedPaths: manifest.storedPaths)
    }
}
