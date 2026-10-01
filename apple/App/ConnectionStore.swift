import Foundation
import Combine

@MainActor final class ConnectionStore: ObservableObject {
    enum Screen {
        case connection(String?)
        case loading
        case libraries([Library])
        case shelf(Library)
    }
    @Published private(set) var screen: Screen = .connection(nil)
    @Published var server: String
    @Published var username: String
    @Published var savedConnectionsPresented = false
    @Published private(set) var savedConnections: [KeychainCredentials.Summary] = []
    @Published private(set) var activeAccount: AccountIdentity?
    /// `api.authorizationRevision` of the opened account; changes on a new sign-in even when the account is the same.
    @Published private(set) var signInRevision: UUID?
    @Published var managementError: String?
    let api: APIClient
    private let vault: KeychainCredentials
    private let playback: ApplePlayback
    private let browserSignIn = OpenIDSignIn()
    private let defaults: UserDefaults
    private var generation = UUID()

    init(api: APIClient, playback: ApplePlayback, vault: KeychainCredentials, defaults: UserDefaults = .standard) {
        self.server = defaults.string(forKey: "previewServer") ?? ""
        self.username = defaults.string(forKey: "previewUsername") ?? ""
        self.api = api
        self.vault = vault
        self.playback = playback
        self.defaults = defaults
        refreshSavedConnections()
    }

    func restore() async {
        guard api.credentials != nil else { return }
        server = api.credentials?.server ?? server
        username = api.credentials?.username ?? username
        if let active = try? vault.activeConnection(), active.id == "migrated-preview-connection", active.libraryID == nil,
           let selected = defaults.string(forKey: "previewLibrary") {
            do { try vault.selectLibrary(selected) }
            catch { managementError = Self.recovery(for: error) }
        }
        await playback.restoreListening()
        await openLibraries()
    }

    func connect(server: String, username: String, password: String) async {
        let request = UUID()
        generation = request
        screen = .loading
        do {
            try await playback.suspendForConnectionChange()
            try await api.login(server: server, username: username, password: password)
            guard request == generation else { return }
            defaults.set(server, forKey: "previewServer")
            defaults.set(username, forKey: "previewUsername")
            self.server = api.credentials?.server ?? server
            self.username = api.credentials?.username ?? username
            refreshSavedConnections()
            await playback.restoreListening()
            await openLibraries()
        } catch {
            guard request == generation else { return }
            screen = .connection(Self.recovery(for: error))
        }
    }

    func openLibrariesForSelection() async {
        do { try vault.selectLibrary(nil) }
        catch { managementError = Self.recovery(for: error); return }
        await openLibraries()
    }

    func connectWithOpenID() async {
        let request = UUID()
        let address = server
        generation = request
        screen = .loading
        do {
            try await playback.suspendForConnectionChange()
            let response = try await browserSignIn.signIn(server: address)
            guard request == generation else { return }
            try api.completeBrowserLogin(server: address, response: response)
            server = api.credentials?.server ?? address
            username = api.credentials?.username ?? ""
            refreshSavedConnections()
            await playback.restoreListening()
            await openLibraries()
        } catch {
            guard request == generation else { return }
            screen = .connection(Self.recovery(for: error))
        }
    }

    func openLibraries() async {
        let request = generation
        screen = .loading
        do {
            let account = try await api.currentAccount()
            guard request == generation else { return }
            activeAccount = account
            signInRevision = api.authorizationRevision
            let libraries = try await api.libraries()
            guard request == generation else { return }
            if let id = try vault.activeConnection()?.libraryID, let library = libraries.first(where: { $0.id == id }) {
                screen = .shelf(library)
            } else { screen = .libraries(libraries) }
        } catch {
            guard request == generation else { return }
            screen = .connection(Self.recovery(for: error))
        }
    }

    func select(_ library: Library) {
        do { try vault.selectLibrary(library.id); screen = .shelf(library) }
        catch { managementError = Self.recovery(for: error) }
    }

    func refreshSavedConnections() {
        do { savedConnections = try vault.summaries() }
        catch { managementError = Self.recovery(for: error) }
    }

    func addServer() {
        savedConnectionsPresented = false
        server = ""
        username = ""
        screen = .connection(nil)
    }

    func cancelConnection() async { await restore() }

    func switchConnection(_ id: String) async {
        let request = UUID()
        let previousScreen = screen
        generation = request
        managementError = nil
        do {
            try await playback.suspendForConnectionChange()
            guard request == generation else { return }
            screen = .loading
            try vault.select(id: id)
            try api.restoreSavedCredentials()
            savedConnectionsPresented = false
            server = api.credentials?.server ?? ""
            username = api.credentials?.username ?? ""
            await playback.restoreListening()
            await openLibraries()
        } catch {
            guard request == generation else { return }
            screen = previousScreen
            managementError = Self.recovery(for: error)
        }
    }

    func signOut() {
        Task {
            do {
                try await playback.suspendForConnectionChange()
                try api.signOut()
                activeAccount = nil
                signInRevision = nil
                generation = UUID()
                defaults.removeObject(forKey: "previewLibrary")
                refreshSavedConnections()
                screen = .connection(nil)
            } catch { managementError = Self.recovery(for: error) }
        }
    }

    /// The message shown for a failure. Its technical cause is kept in diagnostics, redacted, for later recovery.
    static func recovery(for error: Error) -> String {
        let message = recoveryMessage(for: error)
        let category: DiagnosticCategory = error is URLError ? .connection : .server
        NativeDiagnostics.shared.record(category, message, detail: DiagnosticRedactor.describe(error))
        return message
    }

    private static func recoveryMessage(for error: Error) -> String {
        let l10n = NativeStrings.current
        if let failure = error as? URLError {
            switch failure.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return l10n("This server's certificate is not trusted. Check its date and hostname. For your homelab CA, install its profile and enable full trust in Settings → General → About → Certificate Trust Settings, then retry.")
            case .secureConnectionFailed:
                return l10n("A secure TLS connection could not be established. Check the server's certificate chain, hostname and TLS configuration. If you use a homelab CA, confirm its profile and full trust in Settings, then retry.")
            case .appTransportSecurityRequiresSecureConnection:
                return l10n("This address was blocked by the app's HTTP configuration. Use HTTPS or update to a build supporting your local HTTP server.")
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
                return l10n("The server could not be reached. Check its address, Wi-Fi or VPN, then retry. Your saved login is retained.")
            default: return l10n("The connection failed. Check the server address and network, then retry.")
            }
        }
        if error as? APIError == .signInRequired { return l10n("The server no longer accepts this login. Sign in again to continue.") }
        return error.localizedDescription
    }
}
