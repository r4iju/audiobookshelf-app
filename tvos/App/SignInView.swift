import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeStrings) private var l10n
    var reauthenticating = false
    var onAuthenticated: () -> Void = {}
    @State private var server = UserDefaults.standard.string(forKey: CatalogStore.lastServerKey) ?? ""
    @State private var username = UserDefaults.standard.string(forKey: CatalogStore.lastUsernameKey) ?? ""
    @State private var password = ""
    @State private var path: [ReturnFocus] = []
    @FocusState private var focus: ReturnFocus?
    @FocusState private var connectFocused: Bool

    var body: some View {
        // Diagnostics opens from here because a failed first connection happens before Settings exists.
        NavigationStack(path: $path) {
            form.navigationDestination(for: ReturnFocus.self) { _ in DiagnosticsView() }
        }
        .restoresFocus(path: path, to: $focus)
    }

    private var form: some View {
        HStack(alignment: .top, spacing: 110) {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "headphones").font(.system(size: 72)).foregroundStyle(.tint).accessibilityHidden(true)
                Text(reauthenticating ? l10n("Sign in again") : l10n("Listen on the big screen")).font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n("Connect directly to your Audiobook Loft or compatible Audiobookshelf server to stream audiobooks and podcasts."))
                    .font(.title3).foregroundStyle(.secondary)
                Text(Self.supportedSignIn(l10n)).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sign-in-modes")
            }
            .frame(maxWidth: 720, alignment: .leading)
            VStack(alignment: .leading, spacing: 22) {
                // The example sits below the field: a placeholder this long is cut off on the TV.
                TextField(l10n("Server address"), text: $server)
                    .textContentType(.URL).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("serverURL").disabled(reauthenticating)
                Text(l10n("For example, {0}", "https://books.example.com")).font(.caption).foregroundStyle(.secondary)
                TextField(l10n("Username"), text: $username)
                    .textContentType(.username).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("username").disabled(reauthenticating)
                SecureField(l10n("Password"), text: $password).textContentType(.password).accessibilityIdentifier("password")
                if let error = catalog.signInError {
                    Text(error).font(.callout).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sign-in-error")
                }
                Button {
                    guard !catalog.signingIn else { return }
                    Task {
                        await catalog.login(server: server.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: password)
                        // A failure hands focus back to Connect so the remote can retry or open Diagnostics.
                        guard catalog.signedIn, catalog.signInError == nil else {
                            await Task.yield()
                            connectFocused = true
                            return
                        }
                        password = ""
                        onAuthenticated()
                        if reauthenticating { dismiss() }
                    }
                } label: {
                    // The same views throughout: replacing the focused button's content leaves nothing focused on tvOS.
                    HStack {
                        ProgressView().opacity(catalog.signingIn ? 1 : 0).accessibilityHidden(!catalog.signingIn)
                        Text(catalog.signingIn ? l10n("Connecting…") : l10n("Connect"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .nativeGlassButton(prominent: true)
                .disabled(server.isEmpty || username.isEmpty)
                .focused($connectFocused)
                .accessibilityIdentifier("connect")
                Text(l10n("The Apple TV Remote on an iPhone offers a keyboard for easier typing.")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(value: ReturnFocus.diagnostics) { Label(l10n("Diagnostics"), systemImage: "stethoscope") }
                    .nativeGlassButton()
                    .focused($focus, equals: .diagnostics)
                    .accessibilityIdentifier("sign-in-diagnostics")
            }
            .frame(width: 640)
        }
        .padding(90)
    }

    static func supportedSignIn(_ l10n: NativeStrings) -> String {
        l10n("Sign in with an Audiobookshelf username and password. Single sign-on (OpenID) needs a browser, which Apple TV does not provide; ask the server administrator for a local account if you only use single sign-on. HTTPS addresses work when this TV trusts the certificate, including an installed homelab certificate authority, and local HTTP addresses and reverse-proxy paths are supported.")
    }
}
