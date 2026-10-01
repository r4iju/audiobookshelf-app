import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.nativeStrings) private var l10n
    @State private var failure: String?
    @State private var syncing = false
    @State private var path: [ReturnFocus] = []
    @FocusState private var focus: ReturnFocus?
    private static let intervals = [10, 15, 30, 45, 60]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    section(l10n("Server")) {
                        Text(catalog.serverAddress).font(.headline).accessibilityIdentifier("server-address")
                            .accessibilityLabel(l10n("Server address")).accessibilityValue(catalog.serverAddress)
                        if !catalog.username.isEmpty { Text(l10n("Signed in as {0}", catalog.username)).foregroundStyle(.secondary) }
                        Text(SignInView.supportedSignIn(l10n)).font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("auth-modes")
                    }
                    section(l10n("Listening")) {
                        Text(syncStatus).accessibilityIdentifier("sync-status")
                        Button {
                            Task { syncing = true; await player.restoreListening(); syncing = false }
                        } label: { Label(syncing ? l10n("Sending…") : l10n("Send saved listening now"), systemImage: "arrow.triangle.2.circlepath") }
                            .accessibilityIdentifier("send-listening").disabled(syncing)
                        HStack(spacing: 30) {
                            interval(l10n("Skip back"), value: $player.backwardInterval, identifier: "skip-back-interval")
                            interval(l10n("Skip forward"), value: $player.forwardInterval, identifier: "skip-forward-interval")
                        }
                        .focusSection()
                        Toggle(l10n("Rewind a little after a long pause"), isOn: $player.rewindAfterPause)
                    }
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
                .padding(.horizontal, 90)
                .padding(.vertical, 50)
                .frame(maxWidth: 1400, alignment: .leading)
            }
            .navigationDestination(for: ReturnFocus.self) { route in
                if route == .language { LanguageView() } else { DiagnosticsView() }
            }
        }
        .restoresFocus(path: path, to: $focus)
    }

    private var syncStatus: String {
        if let error = player.error, player.session == nil { return error }
        return l10n("Listening on this TV is saved locally first and sent to the server regularly while playing, on pause, on stop and when the app opens.")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            content()
        }
        .focusSection()
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
