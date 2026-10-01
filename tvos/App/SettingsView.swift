import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @State private var failure: String?
    @State private var syncing = false
    private static let intervals = [10, 15, 30, 45, 60]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                section("Server") {
                    Text(catalog.serverAddress).font(.headline).accessibilityIdentifier("server-address")
                    if !catalog.username.isEmpty { Text("Signed in as \(catalog.username)").foregroundStyle(.secondary) }
                    Text(SignInView.supportedSignIn).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("auth-modes")
                }
                section("Listening") {
                    Text(syncStatus).accessibilityIdentifier("sync-status")
                    Button {
                        Task { syncing = true; await player.restoreListening(); syncing = false }
                    } label: { Label(syncing ? "Sending…" : "Send saved listening now", systemImage: "arrow.triangle.2.circlepath") }
                        .accessibilityIdentifier("send-listening").disabled(syncing)
                    HStack(spacing: 30) {
                        interval("Skip back", value: $player.backwardInterval, identifier: "skip-back-interval")
                        interval("Skip forward", value: $player.forwardInterval, identifier: "skip-forward-interval")
                    }
                    .focusSection()
                    Toggle("Rewind a little after a long pause", isOn: $player.rewindAfterPause)
                }
                section("Account") {
                    Button(role: .destructive) {
                        Task {
                            do { try await player.stop(); try catalog.signOut() }
                            catch {
                                catalog.noteAuthentication(error)
                                failure = "Sign-out was cancelled so that listening is not lost: " + CatalogStore.recovery(for: error)
                            }
                        }
                    } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .accessibilityIdentifier("sign-out").disabled(player.preparing || player.seeking)
                    if let failure { Text(failure).foregroundStyle(.orange) }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 50)
            .frame(maxWidth: 1400, alignment: .leading)
        }
    }

    private var syncStatus: String {
        if let error = player.error, player.session == nil { return error }
        return "Listening on this TV is saved locally first and sent to the server regularly while playing, on pause, on stop and when the app opens."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            content()
        }
        .focusSection()
    }

    private func interval(_ title: String, value: Binding<Int>, identifier: String) -> some View {
        Menu {
            ForEach(Self.intervals, id: \.self) { seconds in Button("\(seconds) seconds") { value.wrappedValue = seconds } }
        } label: { Text("\(title): \(value.wrappedValue) s") }
            .accessibilityIdentifier(identifier)
    }
}
