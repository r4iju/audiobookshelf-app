import Foundation

public enum LegacyMigrationError: Error, Equatable {
    case unsupportedLegacySchema(UInt64)
    case differentSourceAlreadyCommitted
    case insufficientSpace(required: Int64, available: Int64)
    case archiveIncomplete
    case archiveUnreadable(String)
    case legacyDatabaseUnreadable(String)
    /// The committed migration no longer matches its record (an adopted file missing, changed, not
    /// a regular file inside `Files`, or journal and outcome disagree). Run `migrate` with the
    /// legacy source again to repair it.
    case committedMigrationDamaged
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
/// verified; its presence plus a committed journal is the commit point), `Files/` (adopted media),
/// `verified.json` (stamps of files whose committed content was last confirmed; losing it only
/// costs a rehash) and `Staging/` (transient). The legacy source is only ever read.
public final class LegacyMigrator {
    public let root: URL
    private let fileSystem: MigrationFileSystem

    public init(root: URL, fileSystem: MigrationFileSystem = LocalMigrationFileSystem()) {
        self.root = root
        self.fileSystem = fileSystem
    }

    private var journalURL: URL { root.appendingPathComponent("state.json") }
    private var outcomeURL: URL { root.appendingPathComponent("outcome.json") }
    private var stagingURL: URL { root.appendingPathComponent("Staging") }
    private var verifiedURL: URL { root.appendingPathComponent("verified.json") }

    /// Where an adopted file can be opened: a regular file inside `Files`, reached through no
    /// symbolic link, holding its committed content. Throws `committedMigrationDamaged` otherwise.
    public func fileURL(for file: MigratedFile) throws -> URL {
        var verified = readVerified()
        guard let url = intactURL(of: file, verified: &verified, trustingStamps: true) else { throw LegacyMigrationError.committedMigrationDamaged }
        writeVerified(verified)
        return url
    }

    /// The committed outcome, with every adopted file checked as `fileURL(for:)` does. Content is
    /// rehashed unless the file's stamp is unchanged since its content was last confirmed, so an
    /// unchanged migration is cheap to check at every launch. Nil when nothing was committed.
    /// Throws `committedMigrationDamaged` when the record no longer holds; `migrate` with the
    /// legacy source repairs it.
    public func committedOutcome() throws -> MigrationOutcome? {
        let outcomeExists = FileManager.default.fileExists(atPath: outcomeURL.path)
        guard let journal = try? readJournal() else {
            if outcomeExists { throw LegacyMigrationError.committedMigrationDamaged }
            return nil
        }
        guard journal.committed else { return nil }
        guard let outcome = try? readOutcome(), outcome.sourceFingerprint == journal.sourceFingerprint,
              verifies(outcome, trustingStamps: true)
        else { throw LegacyMigrationError.committedMigrationDamaged }
        return outcome
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
        // An outcome for this source stays on disk until the next commit replaces it, so a repair
        // (even one interrupted and resumed) holds each file to the digest it was committed with;
        // a source changed since then is reported rather than adopted.
        let previous = (try? readOutcome()).flatMap { $0.sourceFingerprint == fingerprint ? $0 : nil }
        if journal.committed, let previous = previous, verifies(previous, trustingStamps: false) { return previous }
        var recordedDigests: [String: String] = [:]
        for file in previous.map(Self.adoptedFiles) ?? [] { recordedDigests[file.path] = file.sha256 }
        // A repair keeps the journal committed, so a failed repair stays damaged-and-committed
        // to this source instead of looking like no migration happened.
        if !journal.committed { try writeJournal(journal) }

        var plan = MigrationPlan(source: source)
        try? FileManager.default.removeItem(at: stagingURL)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        var adopted: [String: MigratedFile] = [:]
        var pendingTransfer: [(PlannedFile, String)] = []
        for planned in plan.files.values.sorted(by: { $0.key < $1.key }) {
            let digest = try ContainedFile.digest(of: planned.source).sha256
            let destination = "Files/\(planned.destination)"
            if let recorded = source.recordedDigests[planned.legacyPath], recorded != digest {
                plan.report(.fileCorrupt, account: planned.account, item: planned.libraryItemID, path: planned.legacyPath, MigrationPlan.damagedInExportMessage)
                continue
            }
            if let committed = recordedDigests[planned.destination], committed != digest {
                try ContainedFile.clear(destination, under: root, creatingDirectories: false)
                plan.report(.fileCorrupt, account: planned.account, item: planned.libraryItemID, path: planned.legacyPath,
                            "This downloaded file changed after it was migrated, in both apps. It is no longer used; download it again.")
                continue
            }
            if let existing = ContainedFile.url(destination, under: root), (try? ContainedFile.digest(of: existing).sha256) == digest {
                adopted[planned.key] = planned.migrated(sha256: digest)
            } else {
                pendingTransfer.append((planned, digest))
            }
        }

        var copyBudgetChecked = false
        for (planned, digest) in pendingTransfer {
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
            guard try ContainedFile.digest(of: staged).sha256 == digest else {
                try? FileManager.default.removeItem(at: staged)
                plan.report(.fileCorrupt, account: planned.account, item: planned.libraryItemID, path: planned.legacyPath,
                            "This downloaded file changed while it was being moved. The original is unchanged; run the migration again.")
                continue
            }
            let destination = "Files/\(planned.destination)"
            try ContainedFile.clear(destination, under: root, creatingDirectories: true)
            try FileManager.default.moveItem(at: staged, to: root.appendingPathComponent(destination))
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
            guard let sink = secrets, let secret = plan.secret(for: account), !secret.isEmpty else { continue }
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

        // A file adopted earlier stays adopted when its legacy original can no longer be read, as
        // long as the adopted copy still has its committed content.
        var verified = readVerified()
        for (key, file) in previous.map(Self.adoptedFilesByKey) ?? [:] where adopted[key] == nil && plan.files[key] == nil {
            guard intactURL(of: file, verified: &verified, trustingStamps: false) != nil else { continue }
            adopted[key] = file
            plan.retractUnavailable(key: key, legacyPath: file.legacyPath)
        }

        let outcome = plan.outcome(kind: source.kind, fingerprint: fingerprint, accounts: accounts, adopted: adopted)
        try fileSystem.writeAtomically(try MigrationJSON.encoder.encode(outcome), to: outcomeURL)
        journal.committed = true
        try writeJournal(journal)
        let committedPaths = Set(Self.adoptedFiles(of: outcome).map(\.path))
        writeVerified(verified.filter { committedPaths.contains($0.key) })
        try? FileManager.default.removeItem(at: stagingURL)
        return outcome
    }

    private static func adoptedFiles(of outcome: MigrationOutcome) -> [MigratedFile] {
        outcome.downloads.flatMap { $0.files.compactMap(\.file) } + outcome.interruptedDownloads.flatMap { $0.parts.compactMap(\.file) }
    }

    private static func adoptedFilesByKey(_ outcome: MigrationOutcome) -> [String: MigratedFile] {
        var files: [String: MigratedFile] = [:]
        for download in outcome.downloads {
            for file in download.files.compactMap(\.file) { files[MigrationPlan.fileKey(download.account, file.legacyPath)] = file }
        }
        for download in outcome.interruptedDownloads {
            for file in download.parts.compactMap(\.file) { files[MigrationPlan.fileKey(download.account, file.legacyPath)] = file }
        }
        return files
    }

    private func verifies(_ outcome: MigrationOutcome, trustingStamps: Bool) -> Bool {
        var verified = readVerified()
        defer { writeVerified(verified) }
        return Self.adoptedFiles(of: outcome).allSatisfy { intactURL(of: $0, verified: &verified, trustingStamps: trustingStamps) != nil }
    }

    /// The adopted file's location when it is a regular file inside `Files`, reached through real
    /// directories only, with its committed size and digest. `verified` holds stamps of files
    /// whose content was confirmed; with `trustingStamps`, an unchanged stamp stands for a rehash.
    private func intactURL(of file: MigratedFile, verified: inout [String: VerifiedFile], trustingStamps: Bool) -> URL? {
        guard let url = ContainedFile.url("Files/\(file.path)", under: root) else { return nil }
        if trustingStamps, let known = verified[file.path], known.sha256 == file.sha256, known.stamp.size == Int64(file.size),
           ContainedFile.stamp(of: url) == known.stamp {
            return url
        }
        guard let (digest, stamp) = try? ContainedFile.digest(of: url), digest == file.sha256, stamp.size == Int64(file.size) else {
            verified[file.path] = nil
            return nil
        }
        verified[file.path] = VerifiedFile(sha256: digest, stamp: stamp)
        return url
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

    private struct VerifiedFile: Codable, Equatable {
        var sha256: String
        var stamp: FileStamp
    }

    private func readVerified() -> [String: VerifiedFile] {
        (try? MigrationJSON.decoder.decode([String: VerifiedFile].self, from: Data(contentsOf: verifiedURL))) ?? [:]
    }

    /// Best effort: an unwritten record only means the next check rehashes.
    private func writeVerified(_ verified: [String: VerifiedFile]) {
        guard verified != readVerified() else { return }
        try? fileSystem.writeAtomically(try MigrationJSON.encoder.encode(verified), to: verifiedURL)
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
    ///
    /// Without a readable journal, a readable `outcome.json` is the commit record: it is kept, and
    /// only the same source may continue (as committed, with its adopted credentials). An outcome
    /// left by an interrupted commit of a different, uncommitted source is moved aside.
    private func loadJournal(for fingerprint: String) throws -> Journal {
        let existing: Journal?
        do {
            existing = try readJournal()
        } catch {
            try moveAside(journalURL, as: "state")
            existing = nil
        }
        if let journal = existing {
            if journal.sourceFingerprint == fingerprint { return journal }
            if journal.committed { throw LegacyMigrationError.differentSourceAlreadyCommitted }
            if FileManager.default.fileExists(atPath: outcomeURL.path) { try moveAside(outcomeURL, as: "outcome") }
            return Journal(sourceFingerprint: fingerprint)
        }
        if FileManager.default.fileExists(atPath: outcomeURL.path) {
            if let outcome = try? readOutcome() {
                guard outcome.sourceFingerprint == fingerprint else { throw LegacyMigrationError.differentSourceAlreadyCommitted }
                return Journal(sourceFingerprint: fingerprint, credentialsAdopted: outcome.accounts.filter { $0.credentials == .adopted }.map(\.account), committed: true)
            }
            try moveAside(outcomeURL, as: "outcome")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Journal(sourceFingerprint: fingerprint)
    }

    /// Unreadable or superseded records are kept for diagnosis, never deleted.
    private func moveAside(_ url: URL, as name: String) throws {
        let aside = root.appendingPathComponent("\(name).corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.moveItem(at: url, to: aside)
    }

    private func writeJournal(_ journal: Journal) throws {
        try fileSystem.writeAtomically(try MigrationJSON.encoder.encode(journal), to: journalURL)
    }
}
