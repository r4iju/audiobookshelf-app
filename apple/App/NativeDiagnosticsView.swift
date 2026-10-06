import SwiftUI
import UIKit

/// On-device failure history for recovery. Nothing leaves the device unless the person shares the report.
@MainActor final class NativeDiagnostics: ObservableObject {
    static let shared = NativeDiagnostics()
    nonisolated static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDiagnostics/events.json")
    }
    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var storageError: String?
    private let log: DiagnosticLog

    init() {
        NativePresentationReset.applyOnce()
        log = DiagnosticLog(file: Self.file)
        events = log.events
    }

    func record(_ category: DiagnosticCategory, _ message: String, detail: String? = nil) {
        do { try log.record(category, message: message, detail: detail); storageError = nil }
        catch { storageError = DiagnosticRedactor.describe(error) }
        events = log.events
    }

    func clear() {
        do { try log.clear(); storageError = nil }
        catch { storageError = DiagnosticRedactor.describe(error) }
        events = log.events
    }

    /// Listening saved on this device that the server has not acknowledged, read without opening the journal for writing.
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
        guard FileManager.default.fileExists(atPath: ListeningSync.file.path) else { return .success([]) }
        return Result {
            try JSONDecoder().decode(Document.self, from: Data(contentsOf: ListeningSync.file)).records
                .filter { $0.revision > $0.acknowledged }.map(\.media.title)
        }
    }
}

/// Records the failures native screens already show, so a later report explains what the person saw.
private struct DiagnosticObservers: ViewModifier {
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var reading: ReadingStore
    @EnvironmentObject private var connection: ConnectionStore
    func body(content: Content) -> some View {
        content
            .onChange(of: player.error) { error in
                guard let error else { return }
                NativeDiagnostics.shared.record(player.isProgressFailure ? .sync : .media, error, detail: player.title.isEmpty ? nil : "Item: " + player.title)
            }
            .onChange(of: player.bookmarkError) { error in if let error { NativeDiagnostics.shared.record(.server, error, detail: "Bookmarks") } }
            .onChange(of: downloads.error) { error in if let error { NativeDiagnostics.shared.record(.download, error) } }
            .onChange(of: reading.error) { error in if let error { NativeDiagnostics.shared.record(.reading, error) } }
            .onChange(of: connection.managementError) { error in if let error { NativeDiagnostics.shared.record(.connection, error, detail: "Saved connections") } }
    }
}
extension View {
    func recordsDiagnostics() -> some View { modifier(DiagnosticObservers()) }
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

struct NativeDiagnosticsView: View {
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var downloads: NativeDownloads
    @ObservedObject private var diagnostics = NativeDiagnostics.shared
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var showAddress = false
    @State private var confirmingClear = false
    @State private var sharing = false
    @State private var pending = NativeDiagnostics.pendingListening()

    var body: some View {
        // Recent events come first: they explain the failure the person is recovering from.
        ShelfList {
            Section {
                Toggle(l10n("Show server address"), isOn: $showAddress).accessibilityIdentifier("diagnostic-show-address")
            }
            Section(header: Text(l10n("Recent events")).foregroundColor(ShelfStyle.secondaryText), footer: Text(l10n("Events stay on this device. Passwords, tokens and address credentials are removed before they are saved.")).foregroundColor(ShelfStyle.secondaryText)) {
                if diagnostics.events.isEmpty { Text(l10n("No problems recorded")).foregroundColor(ShelfStyle.secondaryText) }
                ForEach(diagnostics.events.reversed()) { event in
                    let shown = event.presented(maskingAddresses: !showAddress)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n(event.category.title)).font(.caption.bold()).foregroundColor(ShelfStyle.accent)
                            Spacer()
                            Text(event.lastDate, style: .relative).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                        }
                        Text(shown.message)
                        if let detail = shown.detail { Text(detail).font(.system(.caption, design: .monospaced)).foregroundColor(ShelfStyle.secondaryText) }
                        if event.count > 1 { Text(l10n("Repeated {0} times", event.count)).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("diagnostic-event")
                }
            }
            Section(header: Text(l10n("Status")).foregroundColor(ShelfStyle.secondaryText)) {
                ForEach(statusLines(), id: \.id) { line in
                    Group {
                        if sizeCategory.isAccessibilityCategory {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.label).foregroundColor(ShelfStyle.secondaryText)
                                Text(line.value)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.label).foregroundColor(ShelfStyle.secondaryText)
                                Spacer()
                                Text(line.value).multilineTextAlignment(.trailing)
                            }
                        }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier(line.id)
                }
            }
            Section(footer: Text(l10n("Sharing opens the system share sheet. Review the report before sending it.")).foregroundColor(ShelfStyle.secondaryText)) {
                NavigationLink(destination: DiagnosticReportView(report: report())) { Text(l10n("Preview report")) }.accessibilityIdentifier("diagnostic-preview")
                Button(l10n("Share report")) { NativeHaptic.impact("logs"); sharing = true }.accessibilityIdentifier("diagnostic-share")
                Button(l10n("Copy report")) { NativeHaptic.impact("logs"); UIPasteboard.general.string = report() }.accessibilityIdentifier("diagnostic-copy")
                Button(l10n("Clear events")) { confirmingClear = true }.foregroundColor(.red).disabled(diagnostics.events.isEmpty).accessibilityIdentifier("diagnostic-clear")
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Diagnostics")).navigationBarTitleDisplayMode(.inline)
            .onAppear { pending = NativeDiagnostics.pendingListening() }
            .alert(isPresented: $confirmingClear) {
                Alert(title: Text(l10n("Clear events?")), message: Text(l10n("The recorded problems are removed from this device.")),
                      primaryButton: .destructive(Text(l10n("Clear"))) { NativeHaptic.impact("logs"); diagnostics.clear() }, secondaryButton: .cancel(Text(l10n("Cancel"))))
            }
            .sheet(isPresented: $sharing) { DiagnosticShareSheet(text: report()) }
    }

    private struct StatusLine { let id: String; let label: String; let value: String; let english: String }

    private func statusLines() -> [StatusLine] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let device = UIDevice.current
        var lines = [
            StatusLine(id: "diagnostic-version", label: l10n("Version"), value: version, english: "Version"),
            StatusLine(id: "diagnostic-system", label: l10n("System"), value: "\(device.systemName) \(device.systemVersion), \(device.model)", english: "System"),
            StatusLine(id: "diagnostic-language", label: l10n("Language"), value: l10n.language.code, english: "Language"),
            StatusLine(id: "diagnostic-server", label: l10n("Server"), value: connection.server.isEmpty ? l10n("Not connected") : display(connection.server), english: "Server"),
            StatusLine(id: "diagnostic-connection", label: l10n("Connection"), value: connectionState, english: "Connection"),
            StatusLine(id: "diagnostic-network", label: l10n("Network preferences"), value: "\(AppleNetworkPolicy.read(AppleNetworkPolicy.streamingKey).rawValue) / \(AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey).rawValue)", english: "Network preferences"),
            StatusLine(id: "diagnostic-playback", label: l10n("Playback"), value: playbackState, english: "Playback"),
            StatusLine(id: "diagnostic-pending-listening", label: l10n("Listening waiting to sync"), value: pendingState, english: "Listening waiting to sync"),
            StatusLine(id: "diagnostic-downloads", label: l10n("Downloads"), value: "\(downloads.entries.count)", english: "Downloads")
        ]
        if let failure = diagnostics.storageError { lines.append(StatusLine(id: "diagnostic-storage", label: l10n("Diagnostics storage"), value: display(failure), english: "Diagnostics storage")) }
        return lines
    }

    private var connectionState: String {
        switch connection.screen {
        case .connection(let error): return error == nil ? l10n("Signed out") : l10n("Failed")
        case .loading: return l10n("Connecting")
        case .libraries: return l10n("Choosing a library")
        case .shelf(let library): return library.name + " (" + library.mediaType + ")"
        }
    }
    private var playbackState: String {
        guard !player.title.isEmpty, player.session != nil || player.preparing || player.error != nil else { return l10n("Idle") }
        let state = player.preparing ? l10n("Preparing audio…") : player.playing ? l10n("Playing") : player.error != nil ? l10n("Failed") : l10n("Paused")
        return player.title + " · " + state
    }
    private var pendingState: String {
        switch pending {
        case .success(let titles): return titles.isEmpty ? "0" : "\(titles.count): " + titles.joined(separator: ", ")
        case .failure(let error): return l10n("Unreadable") + " (" + display(DiagnosticRedactor.describe(error)) + ")"
        }
    }
    private func display(_ text: String) -> String { DiagnosticRedactor.redact(text, maskingAddresses: !showAddress) }

    /// Labels in the shared report stay in English so maintainers can read it; values are what the screen shows.
    private func report() -> String {
        let status = statusLines().map { DiagnosticReport.Line($0.english, $0.value) }
        return DiagnosticReport.text(sections: [.init(title: "Status", lines: status)], events: diagnostics.events, generated: Date(), maskingAddresses: !showAddress)
    }
}

private struct DiagnosticReportView: View {
    @Environment(\.nativeStrings) private var l10n
    let report: String
    var body: some View {
        ScrollView {
            Text(report).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding()
                .accessibilityIdentifier("diagnostic-report")
        }.navigationTitle(l10n("Report"))
    }
}

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
