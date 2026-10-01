import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss
    var reauthenticating = false
    var onAuthenticated: () -> Void = {}
    @State private var server = UserDefaults.standard.string(forKey: "lastServer") ?? ""
    @State private var username = UserDefaults.standard.string(forKey: "lastUsername") ?? ""
    @State private var password = ""

    var body: some View {
        HStack(alignment: .top, spacing: 110) {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "headphones").font(.system(size: 80)).foregroundStyle(.tint)
                Text(reauthenticating ? "Sign in again" : "Listen on the big screen").font(.system(size: 56, weight: .bold))
                Text("Connect directly to your Audiobookshelf server to stream audiobooks and podcasts.")
                    .font(.title3).foregroundStyle(.secondary)
                Text(Self.supportedSignIn).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sign-in-modes")
            }
            .frame(maxWidth: 720, alignment: .leading)
            VStack(alignment: .leading, spacing: 22) {
                TextField("Server address, such as https://books.example.com", text: $server)
                    .textContentType(.URL).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("serverURL").disabled(reauthenticating)
                TextField("Username", text: $username)
                    .textContentType(.username).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("username").disabled(reauthenticating)
                SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("password")
                if let error = catalog.signInError {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sign-in-error")
                }
                Button {
                    Task {
                        await catalog.login(server: server.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: password)
                        guard catalog.signedIn, catalog.signInError == nil else { return }
                        password = ""
                        onAuthenticated()
                        if reauthenticating { dismiss() }
                    }
                } label: {
                    HStack { if catalog.signingIn { ProgressView() }; Text(catalog.signingIn ? "Connecting…" : "Connect") }.frame(maxWidth: .infinity)
                }
                .disabled(catalog.signingIn || server.isEmpty || username.isEmpty)
                .accessibilityIdentifier("connect")
                Text("The Apple TV Remote on an iPhone offers a keyboard for easier typing.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 640)
        }
        .padding(90)
    }

    static let supportedSignIn = "Sign in with an Audiobookshelf username and password. Single sign-on (OpenID) needs a browser, which Apple TV does not provide; ask the server administrator for a local account if you only use single sign-on. HTTPS addresses work when this TV trusts the certificate, including an installed homelab certificate authority, and local HTTP addresses and reverse-proxy paths are supported."
}
