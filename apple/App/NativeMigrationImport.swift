import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor final class NativeMigrationStore: ObservableObject {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LegacyMigration", isDirectory: true)
    }
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var preflight: MigrationPreflight?
    @Published private(set) var outcome: MigrationOutcome?
    @Published private(set) var summary: String?
    @Published private(set) var adoptionIssues: [String] = []
    private let adopter: NativeMigrationAdoption
    private let player: ApplePlayback

    init(adopter: NativeMigrationAdoption, player: ApplePlayback) {
        self.adopter = adopter
        self.player = player
    }
    /// Discards the user's progress for the media so that carried-over legacy listening and
    /// positions cannot bring it back. A reset that throws after it was saved stays on hold and is
    /// finished by the next attempt, start or listening restore.
    func resetProgress(account: AccountIdentity, itemID: String, episodeID: String?) async throws -> CurrentUser {
        try await player.resetProgress(account: account, itemID: itemID, episodeID: episodeID, adoption: adopter)
    }
    private var selectedURL: URL?
    private var selectedFingerprint: String?
    private var syncPending = false
    private var selectionToken: UUID?
    private enum ErrorOrigin { case source, adoption }
    private var errorOrigin = ErrorOrigin.source

    func beginSelection() -> UUID? {
        guard !busy, selectionToken == nil else { return nil }
        let token = UUID()
        selectionToken = token
        return token
    }

    func finishSelection(_ url: URL?, token: UUID) async {
        guard selectionToken == token else { return }
        if let url { await choose(url) }
        selectionToken = nil
        if syncPending { finishOperation() }
    }

    private func finishOperation() {
        busy = false
        if syncPending, selectionToken == nil {
            syncPending = false
            Task { await sync() }
        }
    }

    func sync() async {
        guard !busy, selectionToken == nil else { syncPending = true; return }
        guard outcome != nil else { return }
        busy = true
        defer { finishOperation() }
        let report = await adopter.sync()
        do {
            if let outcome { try await apply(outcome) }
            adoptionIssues += report.failures
        } catch { self.error = Self.message(error) }
    }

    func loadCommitted() async {
        guard !busy, selectionToken == nil else { return }
        busy = true; error = nil; errorOrigin = .source
        defer { finishOperation() }
        do {
            let root = Self.root
            let value = try await Task.detached { try LegacyMigrator(root: root).committedOutcome() }.value
            outcome = value
            if let value { try await apply(value) }
        } catch { self.error = Self.message(error) }
    }

    func choose(_ url: URL) async {
        guard !busy else { return }
        busy = true; error = nil; errorOrigin = .source; preflight = nil; selectedURL = nil; selectedFingerprint = nil
        defer { finishOperation() }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let root = Self.root
            let result = try await Task.detached {
                let source = try LegacyArchive.open(url)
                return (try source.fingerprint, try LegacyMigrator(root: root).preflight(source))
            }.value
            if let outcome, outcome.sourceFingerprint != result.0 { throw LegacyMigrationError.differentSourceAlreadyCommitted }
            selectedURL = url; selectedFingerprint = result.0; preflight = result.1
        } catch { self.error = Self.message(error) }
    }

    func importSelected() async {
        guard !busy, let url = selectedURL, let fingerprint = selectedFingerprint else { return }
        busy = true; error = nil; errorOrigin = .source
        defer { finishOperation() }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let root = Self.root
            let value = try await Task.detached {
                let source = try LegacyArchive.open(url)
                guard try source.fingerprint == fingerprint else { throw LegacyMigrationError.archiveUnreadable("The export changed. Choose it again before importing.") }
                return try LegacyMigrator(root: root).migrate(source)
            }.value
            outcome = value
            let files = root.appendingPathComponent("Files", isDirectory: true)
            if FileManager.default.fileExists(atPath: files.path) {
                var location = files
                var resource = URLResourceValues(); resource.isExcludedFromBackup = true
                try location.setResourceValues(resource)
            }
            try await apply(value)
            preflight = nil; selectedURL = nil; selectedFingerprint = nil
            syncPending = true
        } catch { self.error = Self.message(error) }
    }

    private func apply(_ value: MigrationOutcome) async throws {
        do {
            let report = try await adopter.apply(outcome: value, migrator: LegacyMigrator(root: Self.root))
            applyPlaybackPreferences(report.settings.applied)
            if NativeLanguage.adoptLegacy(value.settings.device?.languageCode) {
                NativeLanguageSetting.shared.choose(NativeLanguage.current.code)
            }
            summary = report.summary
            adoptionIssues = report.issues
            if errorOrigin == .adoption { error = nil }
        } catch {
            errorOrigin = .adoption
            throw error
        }
    }

    private func applyPlaybackPreferences(_ applied: [String]) {
        let defaults = UserDefaults.standard
        for key in applied {
            switch key {
            case "previewSkipForward": player.forwardInterval = defaults.integer(forKey: key)
            case "previewSkipBackward": player.backwardInterval = defaults.integer(forKey: key)
            case "previewResumeRewind": player.rewindAfterPause = defaults.bool(forKey: key)
            case "previewMediaSeeking": player.allowMediaSeeking = defaults.bool(forKey: key)
            case "previewSleepFade": player.fadeSleepTimer = defaults.bool(forKey: key)
            case "previewChapterTrack": player.chapterTrack = defaults.bool(forKey: key)
            case "previewPlaybackSpeed":
                player.speed = defaults.float(forKey: key)
                player.changeSpeed()
            default: break
            }
        }
    }

    private static func message(_ error: Error) -> String {
        let l10n = NativeStrings.current
        switch error {
        case LegacyMigrationError.archiveIncomplete: return l10n("Choose the complete export package or the folder containing archive.json. An unfinished export cannot be imported.")
        case LegacyMigrationError.archiveUnreadable(let message): return message
        case LegacyMigrationError.differentSourceAlreadyCommitted: return l10n("An earlier import is already saved. Choose its original export to retry or repair it.")
        case LegacyMigrationError.committedMigrationDamaged: return l10n("Some imported files need repair. Choose the original export again. Your saved data is retained.")
        case LegacyMigrationError.insufficientSpace(let required, let available):
            return l10n("Import needs {0}; {1} is available. Free space and retry.", ByteCountFormatter.string(fromByteCount: required, countStyle: .file), ByteCountFormatter.string(fromByteCount: available, countStyle: .file))
        case LegacyMigrationError.unsupportedLegacySchema: return l10n("This export uses an unsupported database version. Keep it and update the importer before trying again.")
        default: return l10n("The import could not finish. Your original export and saved data are retained. Choose the export again to retry.")
        }
    }
}

struct NativeMigrationImport: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.presentationMode) private var presentation
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: NativeMigrationStore
    @State private var choosing = false
    @State private var selectionToken: UUID?

    var body: some View {
        ShelfList {
            Section(header: Text(l10n("Keep your listening")).foregroundColor(ShelfStyle.secondaryText)) {
                Text(l10n("Export your data from the previous app, then choose the export package here."))
                Text(l10n("Your previous app and its original files stay available.")).foregroundColor(ShelfStyle.secondaryText)
                Text(l10n("Sign in again after importing to access each account.")).foregroundColor(ShelfStyle.secondaryText)
                Button(l10n("Choose export")) {
                    selectionToken = store.beginSelection()
                    choosing = selectionToken != nil
                }.disabled(store.busy)
            }
            if store.busy { ProgressView(l10n("Working on your import…")) }
            if let error = store.error {
                Section {
                    Text(error).foregroundColor(.red)
                    if store.outcome != nil { Button(l10n("Retry saved import")) { Task { await store.loadCommitted() } }.disabled(store.busy) }
                }
            }
            if let preflight = store.preflight {
                Section(header: Text(l10n("Ready to import")).foregroundColor(ShelfStyle.secondaryText)) {
                    Text(l10n("{0} accounts", preflight.accounts.count))
                    Text(l10n("{0} files available", preflight.adoptableFiles))
                    Text(l10n("Up to {0} of additional space", ByteCountFormatter.string(fromByteCount: preflight.requiredBytesIfCopied, countStyle: .file)))
                    Text(l10n("Missing files and unclear account ownership will be retained for recovery.")).font(.footnote).foregroundColor(ShelfStyle.secondaryText)
                    Button(l10n(store.outcome == nil ? "Import data" : "Repair and retry import")) { Task { await store.importSelected() } }.disabled(store.busy)
                }
                issueRows(preflight.issues)
            }
            if let outcome = store.outcome {
                if let summary = store.summary {
                    Section(header: Text(l10n("Saved import")).foregroundColor(ShelfStyle.secondaryText)) {
                        Text(summary)
                        Button(l10n("Retry pending work")) { Task { await store.sync() } }.disabled(store.busy)
                    }
                }
                Section(header: Text(l10n("Accounts")).foregroundColor(ShelfStyle.secondaryText)) {
                    ForEach(outcome.accounts.indices, id: \.self) { index in
                        let account = outcome.accounts[index]
                        VStack(alignment: .leading, spacing: 8) {
                            Text(account.name.isEmpty ? account.username : account.name).font(.headline)
                            Text(account.account.server).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                            Button(l10n("Sign in to this account")) {
                                connection.addServer()
                                connection.server = account.account.server
                                connection.username = account.username
                                presentation.wrappedValue.dismiss()
                            }
                        }.padding(.vertical, 4)
                    }
                }
                issueRows(outcome.issues)
                if !store.adoptionIssues.isEmpty {
                    Section(header: Text(l10n("Needs attention")).foregroundColor(ShelfStyle.secondaryText)) {
                        ForEach(store.adoptionIssues.indices, id: \.self) { index in Text(store.adoptionIssues[index]).font(.callout) }
                    }
                }
                Section(footer: Text(l10n("Available files and unresolved records remain saved, including formats this app cannot open yet.")).foregroundColor(ShelfStyle.secondaryText)) {
                    Text(l10n("{0} listening records retained", outcome.pendingSessions.count))
                    Text(l10n("{0} interrupted downloads retained", outcome.interruptedDownloads.count))
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Import your data")).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosing, onDismiss: {
                if let token = selectionToken {
                    selectionToken = nil
                    Task { await store.finishSelection(nil, token: token) }
                }
            }) {
                MigrationFilePicker { url in
                    choosing = false
                    if let token = selectionToken {
                        Task { await store.finishSelection(url, token: token) }
                        selectionToken = nil
                    }
                }
            }
            .onAppear { Task { await store.loadCommitted() } }
    }

    @ViewBuilder private func issueRows(_ issues: [MigrationIssue]) -> some View {
        if !issues.isEmpty {
            Section(header: Text(l10n("Import notes")).foregroundColor(ShelfStyle.secondaryText)) {
                ForEach(issues.indices, id: \.self) { index in Text(issues[index].message).font(.callout) }
            }
        }
    }
}

private struct MigrationFilePicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .package, .data], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.isModalInPresentation = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
