import SwiftUI

/// Failures this TV has shown, kept on the device for recovery. Apple TV has no share sheet or pasteboard, so nothing leaves it.
@MainActor final class TVDiagnostics: ObservableObject {
    static let shared = TVDiagnostics()
    /// Caches, because tvOS keeps no other app files reliably; losing old events under storage pressure is acceptable.
    nonisolated static var file: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDiagnostics/events.json")
    }
    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var storageError: String?
    private let log: DiagnosticLog

    init() {
        log = DiagnosticLog(file: Self.file)
        events = log.events
    }

    func record(_ category: DiagnosticCategory, _ message: String, detail: String? = nil) {
        do { try log.record(category, message: message, detail: detail); storageError = nil }
        catch { storageError = DiagnosticRedactor.describe(error) }
        events = log.events
    }

    /// Records a failure in the English wording of the message the screen showed, so it reads the same in any language.
    func record(_ failure: Error, detail: String?) {
        if failure is CancellationError { return }
        record(Self.category(of: failure), CatalogStore.recovery(for: failure, in: NativeStrings(language: .english)), detail: detail)
    }

    func clear() {
        do { try log.clear(); storageError = nil }
        catch { storageError = DiagnosticRedactor.describe(error) }
        events = log.events
    }

    nonisolated static func category(of failure: Error) -> DiagnosticCategory {
        switch failure {
        case is URLError: return .connection
        case APIError.invalidServer, APIError.signInRequired, APIError.http(401): return .connection
        case APIError.noAudio, APIError.unsafeMediaURL: return .media
        default: return .server
        }
    }

    /// Titles of listening this TV saved that the server has not acknowledged, read without opening the journal for writing.
    static func pendingListening() -> Result<[String], Error> {
        struct Document: Decodable {
            struct Record: Decodable {
                struct Media: Decodable { let title: String }
                let media: Media
                let revision: UInt64
                let acknowledged: UInt64
            }
            let records: [Record]
        }
        return Result {
            // The TV keeps the journal in defaults; the file is only its older location.
            var stored = UserDefaults.standard.data(forKey: "NativeListeningJournal")
            if stored == nil, FileManager.default.fileExists(atPath: ListeningSync.file.path) { stored = try Data(contentsOf: ListeningSync.file) }
            guard let stored else { return [] }
            return try JSONDecoder().decode(Document.self, from: stored).records.filter { $0.revision > $0.acknowledged }.map(\.media.title)
        }
    }
}

extension DiagnosticCategory {
    var title: String {
        switch self {
        case .connection: return "Connection"
        case .server: return "Server"
        case .media: return "Media"
        case .sync: return "Sync"
        case .download: return "Downloads"
        case .reading: return "Reading"
        case .podcast: return "Podcasts"
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @ObservedObject private var diagnostics = TVDiagnostics.shared
    @Environment(\.nativeStrings) private var l10n
    @State private var showAddress = false
    @State private var confirmingClear = false
    @State private var pending = TVDiagnostics.pendingListening()

    var body: some View {
        // Recent events come first: they explain the failure the person is recovering from.
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(l10n("Diagnostics")).font(.title2.bold())
                    Text(l10n("Events stay on this device. Passwords, tokens and address credentials are removed before they are saved."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle(l10n("Show server address"), isOn: $showAddress).accessibilityIdentifier("diagnostic-show-address")
                }
                .focusSection()
                VStack(alignment: .leading, spacing: 18) {
                    Text(l10n("Recent events")).font(.title3.bold())
                    if diagnostics.events.isEmpty {
                        Text(l10n("No problems recorded")).foregroundStyle(.secondary).accessibilityIdentifier("diagnostic-empty")
                    }
                    ForEach(diagnostics.events.reversed()) { event in
                        DiagnosticRow { eventText(event) }.accessibilityIdentifier("diagnostic-event")
                    }
                    Button(l10n("Clear events"), role: .destructive) { confirmingClear = true }
                        .disabled(diagnostics.events.isEmpty).accessibilityIdentifier("diagnostic-clear")
                }
                .focusSection()
                VStack(alignment: .leading, spacing: 18) {
                    Text(l10n("Status")).font(.title3.bold())
                    ForEach(statusLines(), id: \.id) { line in
                        DiagnosticRow {
                            Text(line.label).foregroundStyle(.secondary)
                            Text(line.value)
                        }
                        .accessibilityIdentifier(line.id)
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 50)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .onAppear { pending = TVDiagnostics.pendingListening() }
        .alert(l10n("Clear events?"), isPresented: $confirmingClear) {
            Button(l10n("Clear"), role: .destructive) { diagnostics.clear() }
            Button(l10n("Cancel"), role: .cancel) {}
        } message: {
            Text(l10n("The recorded problems are removed from this device."))
        }
    }

    @ViewBuilder private func eventText(_ event: DiagnosticEvent) -> some View {
        let shown = event.presented(maskingAddresses: !showAddress)
        HStack {
            Text(l10n(event.category.title)).font(.callout.bold()).foregroundStyle(.tint)
            Spacer()
            Text(event.lastDate, style: .relative).font(.callout).foregroundStyle(.secondary)
        }
        Text(l10n(shown.message))
        if let detail = shown.detail { Text(detail).font(.callout.monospaced()).foregroundStyle(.secondary) }
        if event.count > 1 { Text(l10n("Repeated {0} times", event.count)).font(.callout).foregroundStyle(.secondary) }
    }

    private struct StatusLine { let id: String; let label: String; let value: String }

    private func statusLines() -> [StatusLine] {
        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        var lines = [
            StatusLine(id: "diagnostic-version", label: l10n("Version"), value: "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"),
            StatusLine(id: "diagnostic-system", label: l10n("System"), value: "\(device.systemName) \(device.systemVersion), \(device.model)"),
            StatusLine(id: "diagnostic-language", label: l10n("Language"), value: l10n.language.code),
            StatusLine(id: "diagnostic-server", label: l10n("Server"), value: catalog.serverAddress.isEmpty ? l10n("Not connected") : display(catalog.serverAddress)),
            StatusLine(id: "diagnostic-account", label: l10n("Account"), value: catalog.signedIn ? l10n("Signed in as {0}", catalog.username) : l10n("Signed out")),
            StatusLine(id: "diagnostic-playback", label: l10n("Playback"), value: playbackState),
            StatusLine(id: "diagnostic-pending-listening", label: l10n("Listening waiting to sync"), value: pendingState)
        ]
        if let failure = diagnostics.storageError {
            lines.append(StatusLine(id: "diagnostic-storage", label: l10n("Diagnostics storage"), value: display(failure)))
        }
        return lines
    }

    private var playbackState: String {
        guard !player.title.isEmpty, player.session != nil || player.preparing || player.error != nil else { return l10n("Idle") }
        let state = player.preparing ? l10n("Loading") : player.playing ? l10n("Playing") : player.error != nil ? l10n("Failed") : l10n("Paused")
        return player.title + " · " + state
    }

    private var pendingState: String {
        switch pending {
        case .success(let titles): return titles.isEmpty ? "0" : "\(titles.count): " + titles.joined(separator: ", ")
        case .failure(let error): return l10n("Unreadable") + " (" + display(DiagnosticRedactor.describe(error)) + ")"
        }
    }

    private func display(_ text: String) -> String { DiagnosticRedactor.redact(text, maskingAddresses: !showAddress) }
}

/// Read-only text the remote can still reach, so a long list scrolls and VoiceOver reads each entry as one.
private struct DiagnosticRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(focused ? 0.18 : 0.06)))
            .focusable()
            .focused($focused)
            .accessibilityElement(children: .combine)
    }
}
