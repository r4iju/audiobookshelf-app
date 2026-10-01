import Foundation

/// Credential-free export of a legacy installation that can cross the sandbox boundary through the
/// Files app: a directory holding `files/<legacy path>` and `archive.json`. The archive is built
/// under `<name>.partial` and renamed only after `archive.json` (written last) is complete, so a
/// directory without `archive.json` is always an interrupted export.
public enum LegacyArchive {
    public static let manifestName = "archive.json"
    public static let formatVersion = 1

    private struct Manifest: Codable {
        var formatVersion: Int
        var snapshot: LegacySnapshot
        var digests: [String: String]
    }

    @discardableResult
    public static func write(_ snapshot: LegacySnapshot, documents: URL, to destination: URL) throws -> URL {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let partial = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".partial")
        try? FileManager.default.removeItem(at: partial)
        let files = partial.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        var exported = snapshot
        exported.preferences = LegacyStorageAllowlist.preferences(snapshot.preferences)
        exported.webStorage = LegacyStorageAllowlist.webStorage(snapshot.webStorage)

        // Reuse the migration's path validation so the archive never contains anything a migration
        // from Documents would refuse to read.
        let plan = MigrationPlan(source: LegacySource(kind: .inPlace, snapshot: exported, filesRoot: documents))
        var digests: [String: String] = [:]
        for planned in plan.files.values {
            let target = files.appendingPathComponent(planned.legacyPath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: planned.source, to: target)
            digests[planned.legacyPath] = try LegacyMigrator.sha256(of: target)
        }

        let manifest = try MigrationJSON.encoder.encode(Manifest(formatVersion: formatVersion, snapshot: exported, digests: digests))
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
        return LegacySource(kind: .archive, snapshot: manifest.snapshot, filesRoot: url.appendingPathComponent("files"), recordedDigests: manifest.digests)
    }
}
