import CryptoKit
import Foundation

public enum LegacyMigrationError: Error, Equatable {
    case unsupportedLegacySchema(UInt64)
    case differentSourceAlreadyCommitted
    case insufficientSpace(required: Int64, available: Int64)
    case archiveIncomplete
    case archiveUnreadable(String)
    case legacyDatabaseUnreadable(String)
}

public struct MigrationPreflight: Equatable {
    public var accounts: [MigrationAccount]
    public var adoptableFiles: Int
    public var requiredBytesIfCopied: Int64
    public var availableBytes: Int64
    public var issues: [MigrationIssue]
}

/// Adopts a legacy installation into the native app's container.
///
/// Layout under `root`: `state.json` (journal), `outcome.json` (written once everything is
/// verified; its presence plus a committed journal is the commit point), `Files/` (adopted media)
/// and `Staging/` (transient). The legacy source is only ever read.
public final class LegacyMigrator {
    public let root: URL
    private let fileSystem: MigrationFileSystem

    public init(root: URL, fileSystem: MigrationFileSystem = LocalMigrationFileSystem()) {
        self.root = root
        self.fileSystem = fileSystem
    }

    private var journalURL: URL { root.appendingPathComponent("state.json") }
    private var outcomeURL: URL { root.appendingPathComponent("outcome.json") }
    private var filesURL: URL { root.appendingPathComponent("Files") }
    private var stagingURL: URL { root.appendingPathComponent("Staging") }

    public func fileURL(for file: MigratedFile) -> URL {
        filesURL.appendingPathComponent(file.path)
    }

    public func committedOutcome() throws -> MigrationOutcome? {
        guard let journal = try? readJournal(), journal.committed else { return nil }
        return try? readOutcome()
    }

    public func preflight(_ source: LegacySource) throws -> MigrationPreflight {
        try requireSupportedSchema(source)
        let plan = MigrationPlan(source: source)
        var ancestor = root
        while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.pathComponents.count > 1 {
            ancestor.deleteLastPathComponent()
        }
        return MigrationPreflight(
            accounts: plan.accounts.map(\.account),
            adoptableFiles: plan.files.count,
            requiredBytesIfCopied: plan.files.values.reduce(0) { $0 + $1.size },
            availableBytes: try fileSystem.availableCapacity(at: ancestor),
            issues: plan.issues
        )
    }

    public func migrate(_ source: LegacySource, secrets: MigrationSecretSink? = nil) throws -> MigrationOutcome {
        try requireSupportedSchema(source)
        let fingerprint = try source.fingerprint
        var journal = try loadJournal(for: fingerprint)
        if journal.committed, let outcome = try? readOutcome() {
            return outcome
        }
        journal.committed = false
        try writeJournal(journal)

        var plan = MigrationPlan(source: source)
        try? FileManager.default.removeItem(at: stagingURL)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)

        var adopted: [String: MigratedFile] = [:]
        var pendingTransfer: [(PlannedFile, String)] = []
        for planned in plan.files.values.sorted(by: { $0.key < $1.key }) {
            let digest = try Self.sha256(of: planned.source)
            if let recorded = source.recordedDigests[planned.legacyPath], recorded != digest {
                plan.report(.fileCorrupt, account: planned.account, item: planned.libraryItemID, path: planned.legacyPath,
                            "This downloaded file was damaged in the export. The original in the old app is unchanged; export again or download it again.")
                continue
            }
            let destination = filesURL.appendingPathComponent(planned.destination)
            if FileManager.default.fileExists(atPath: destination.path), (try? Self.sha256(of: destination)) == digest {
                adopted[planned.key] = planned.migrated(sha256: digest)
            } else {
                pendingTransfer.append((planned, digest))
            }
        }

        var copyBudgetChecked = false
        for (planned, digest) in pendingTransfer {
            let destination = filesURL.appendingPathComponent(planned.destination)
            let staged = stagingURL.appendingPathComponent(UUID().uuidString)
            do {
                try fileSystem.link(planned.source, to: staged)
            } catch {
                if !copyBudgetChecked {
                    let required = pendingTransfer.filter { adopted[$0.0.key] == nil }.reduce(Int64(0)) { $0 + $1.0.size }
                    let available = try fileSystem.availableCapacity(at: root)
                    guard required <= available else { throw LegacyMigrationError.insufficientSpace(required: required, available: available) }
                    copyBudgetChecked = true
                }
                try fileSystem.copy(planned.source, to: staged)
            }
            guard try Self.sha256(of: staged) == digest else {
                try? FileManager.default.removeItem(at: staged)
                plan.report(.fileCorrupt, account: planned.account, item: planned.libraryItemID, path: planned.legacyPath,
                            "This downloaded file changed while it was being moved. The original is unchanged; run the migration again.")
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            adopted[planned.key] = planned.migrated(sha256: digest)
            journal.adopted[planned.destination] = digest
            try writeJournal(journal)
        }

        var accounts = plan.accounts
        for index in accounts.indices {
            let account = accounts[index]
            if journal.credentialsAdopted.contains(account.account) {
                accounts[index].credentials = .adopted
                continue
            }
            guard let sink = secrets, let secret = plan.secret(for: account, from: source), !secret.isEmpty else { continue }
            do {
                try sink.adopt(secret, for: account)
            } catch {
                continue
            }
            accounts[index].credentials = .adopted
            journal.credentialsAdopted.append(account.account)
            try writeJournal(journal)
        }
        for account in accounts where account.credentials == .reauthenticationRequired {
            plan.report(.reauthenticationRequired, account: account.account, item: nil, path: nil,
                        "Sign in to \(account.account.server) as \(account.username.isEmpty ? "this user" : account.username) again. Downloads, progress and unsent listening for this account are kept and become available after sign-in.")
        }

        let outcome = plan.outcome(kind: source.kind, fingerprint: fingerprint, accounts: accounts, adopted: adopted)
        try fileSystem.writeAtomically(try MigrationJSON.encoder.encode(outcome), to: outcomeURL)
        journal.committed = true
        try writeJournal(journal)
        try? FileManager.default.removeItem(at: stagingURL)
        return outcome
    }

    private func requireSupportedSchema(_ source: LegacySource) throws {
        guard source.snapshot.schemaVersion == LegacySnapshot.supportedSchemaVersion else {
            throw LegacyMigrationError.unsupportedLegacySchema(source.snapshot.schemaVersion)
        }
    }

    // MARK: Journal

    private struct Journal: Codable {
        var formatVersion = 1
        var sourceFingerprint: String
        var adopted: [String: String] = [:]
        var credentialsAdopted: [MigrationAccount] = []
        var committed = false
    }

    private func readJournal() throws -> Journal? {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
        return try MigrationJSON.decoder.decode(Journal.self, from: Data(contentsOf: journalURL))
    }

    private func readOutcome() throws -> MigrationOutcome {
        let outcome = try MigrationJSON.decoder.decode(MigrationOutcome.self, from: Data(contentsOf: outcomeURL))
        guard outcome.formatVersion == MigrationOutcome.formatVersion else { throw CocoaError(.fileReadCorruptFile) }
        return outcome
    }

    /// Returns the journal to continue from. An unreadable journal is moved aside (never deleted)
    /// and the migration restarts; adopted files are re-verified by content, so nothing is trusted
    /// from it. A committed migration of different legacy data is never overwritten.
    private func loadJournal(for fingerprint: String) throws -> Journal {
        let existing: Journal?
        do {
            existing = try readJournal()
        } catch {
            let aside = root.appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
            try FileManager.default.moveItem(at: journalURL, to: aside)
            existing = nil
        }
        guard let journal = existing else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return Journal(sourceFingerprint: fingerprint)
        }
        if journal.sourceFingerprint == fingerprint { return journal }
        if journal.committed { throw LegacyMigrationError.differentSourceAlreadyCommitted }
        return Journal(sourceFingerprint: fingerprint)
    }

    private func writeJournal(_ journal: Journal) throws {
        try fileSystem.writeAtomically(try MigrationJSON.encoder.encode(journal), to: journalURL)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hex
    }
}
