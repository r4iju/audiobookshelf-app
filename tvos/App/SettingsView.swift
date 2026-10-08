import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.nativeStrings) private var l10n
    @State private var failure: String?
    @State private var syncing = false
    @State private var waiting = PublicationLedger.Waiting()
    @State private var recoveryFailure: String?
    @State private var confirming = false
    @FocusState private var confirmFocused: Bool
    @State private var path: [ReturnFocus] = []
    @FocusState private var focus: ReturnFocus?
    private static let intervals = [10, 15, 30, 45, 60]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                section(l10n("Apple TV")) {
                    NavigationLink(value: ReturnFocus.language) {
                        Label(l10n("Language") + ": " + l10n.language.name, systemImage: "globe")
                    }
                    .focused($focus, equals: .language)
                    .accessibilityIdentifier("language-setting")
                    NavigationLink(value: ReturnFocus.diagnostics) { Label(l10n("Diagnostics"), systemImage: "stethoscope") }
                        .focused($focus, equals: .diagnostics)
                        .accessibilityIdentifier("diagnostics-setting")
                }
                section(l10n("Server")) {
                    Text(catalog.serverAddress).font(.headline).accessibilityIdentifier("server-address")
                        .accessibilityLabel(l10n("Server address")).accessibilityValue(catalog.serverAddress)
                    if !catalog.username.isEmpty { Text(l10n("Signed in as {0}", catalog.username)).foregroundStyle(.secondary) }
                    TVReadableText(text: SignInView.supportedSignIn(l10n), identifier: "auth-modes")
                }
                section("Audiobook Loft") {
                    NavigationLink(value: ReturnFocus.notices) {
                        Label(l10n("Source and license notices"), systemImage: "doc.text")
                    }
                    .focused($focus, equals: .notices)
                    .accessibilityIdentifier("source-notices")
                }
                if !waiting.isEmpty { savesWaiting }
                section(l10n("Listening")) {
                    Text(syncStatus).accessibilityIdentifier("sync-status")
                    Button {
                        Task { syncing = true; await player.restoreListening(); syncing = false; await refreshWaiting() }
                    } label: { Label(syncing ? l10n("Sending…") : l10n("Send saved listening now"), systemImage: "arrow.triangle.2.circlepath") }
                        .accessibilityIdentifier("send-listening").disabled(syncing)
                    interval(l10n("Skip back"), value: $player.backwardInterval, identifier: "skip-back-interval")
                    interval(l10n("Skip forward"), value: $player.forwardInterval, identifier: "skip-forward-interval")
                    Toggle(l10n("Rewind a little after a long pause"), isOn: $player.rewindAfterPause)
                }
                section(l10n("Account")) {
                    Button(role: .destructive) {
                        Task {
                            do { try await player.stop(); try catalog.signOut() }
                            catch {
                                catalog.noteAuthentication(error)
                                TVDiagnostics.shared.record(error, detail: "Sign-out")
                                failure = l10n("Sign-out was cancelled so that listening is not lost: {0}", CatalogStore.recovery(for: error, in: l10n))
                            }
                        }
                    } label: { Label(l10n("Sign out"), systemImage: "rectangle.portrait.and.arrow.right") }
                        .accessibilityIdentifier("sign-out").disabled(player.preparing || player.seeking)
                    if let failure { Text(failure).foregroundStyle(.orange) }
                }
            }
            .frame(maxWidth: 1400)
            .padding(.horizontal, 90)
            .padding(.vertical, 35)
            .tvNavigationTitle(l10n("Settings"))
            .navigationDestination(for: ReturnFocus.self) { route in
                switch route {
                case .language: LanguageView()
                case .diagnostics: DiagnosticsView()
                case .notices: NoticesView()
                }
            }
        }
        .restoresFocus(path: path, to: $focus)
        .task { await refreshWaiting() }
        .onReceive(NotificationCenter.default.publisher(for: PublicationLedger.changed)) { _ in Task { await refreshWaiting() } }
    }

    /// Server 2.30 cannot tell when a save it never answered has finished; a restart ends it. The
    /// restart is asked for here first, so only one that happens afterwards is confirmed.
    private var savesWaiting: some View {
        section(l10n("Saves waiting")) {
            Text(waiting.unreadable
                 ? l10n("The record of earlier saves could not be read, so the server may still apply any of them. Newer listening stays on this TV until a server restart is confirmed.")
                 : waiting.titles == 1
                 ? l10n("The server never answered a save for one title and may still apply it, which would replace anything newer. Newer listening for that title stays on this TV. Other titles sync as usual.")
                 : l10n("The server never answered saves for {0} titles and may still apply them, which would replace anything newer. Newer listening for those titles stays on this TV. Other titles sync as usual.", waiting.titles))
                .accessibilityIdentifier("publications-waiting")
            Text(l10n("Server {0}, signed in as {1}", catalog.serverAddress, catalog.username)).foregroundStyle(.secondary)
                .accessibilityIdentifier("publications-account")
            if waiting.restartRequested {
                Text(l10n("Now restart the Audiobookshelf server. Only a restart after you chose Start server restart counts. When the server is running again, confirm it here."))
                    .accessibilityIdentifier("restart-instructions")
            } else {
                Text(l10n("Restarting the Audiobookshelf server ends an unanswered save. Choose Start server restart first, then restart the server."))
            }
            // Keep one native List row as the requested restart becomes its confirmation step.
            Button {
                if waiting.restartRequested { confirmRestart() } else { requestRestart() }
            } label: {
                Label(confirming ? l10n("Sending…") : waiting.restartRequested ? l10n("The server has restarted") : l10n("Start server restart"),
                      systemImage: waiting.restartRequested ? "checkmark.circle" : "arrow.clockwise.circle")
            }
            .id("server-restart-step")
            .focused($confirmFocused)
            .accessibilityIdentifier(waiting.restartRequested ? "confirm-server-restarted" : "request-server-restart")
            .disabled(confirming)
            if waiting.restartRequested {
                Button(l10n("Start again")) { requestRestart() }.accessibilityIdentifier("request-server-restart-again").disabled(confirming)
            }
            if let recoveryFailure { Text(recoveryFailure).foregroundStyle(.orange) }
        }
    }

    private func refreshWaiting() async {
        guard let account = try? await catalog.api.currentAccount() else { waiting = PublicationLedger.Waiting(); return }
        waiting = player.publications.waiting(account: account)
    }

    private func requestRestart() {
        Task {
            do {
                try player.requestServerRestart(account: try await catalog.api.currentAccount())
                recoveryFailure = nil
            } catch { recoveryFailure = CatalogStore.recovery(for: error, in: l10n) }
            await refreshWaiting()
            confirmFocused = waiting.restartRequested
        }
    }

    private func confirmRestart() {
        Task {
            confirming = true
            do {
                try player.confirmServerRestarted(account: try await catalog.api.currentAccount())
                recoveryFailure = nil
                await player.restoreListening()
            } catch { recoveryFailure = CatalogStore.recovery(for: error, in: l10n) }
            confirming = false
            await refreshWaiting()
        }
    }

    private var syncStatus: String {
        if let error = player.error, player.session == nil { return error }
        return l10n("Listening on this TV is saved locally first and sent to the server regularly while playing, on pause, on stop and when the app opens.")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            // TV List supplementary headers do not enter its accessibility tree.
            Text(title).font(.headline).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
            content()
        }
    }

    private func interval(_ title: String, value: Binding<Int>, identifier: String) -> some View {
        let current = l10n("{0} seconds", value.wrappedValue)
        return Menu {
            ForEach(Self.intervals, id: \.self) { seconds in Button(l10n("{0} seconds", seconds)) { value.wrappedValue = seconds } }
        } label: { Text(title + ": " + current) }
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
            .accessibilityValue(current)
    }
}
