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
    let api: APIClient
    private let defaults: UserDefaults
    private var generation = UUID()

    init(api: APIClient, defaults: UserDefaults = .standard) {
        self.server = defaults.string(forKey: "previewServer") ?? ""
        self.username = defaults.string(forKey: "previewUsername") ?? ""
        self.api = api
        self.defaults = defaults
    }

    func restore() async {
        guard api.credentials != nil else { return }
        await openLibraries()
    }

    func connect(server: String, username: String, password: String) async {
        let request = UUID()
        generation = request
        screen = .loading
        do {
            try await api.login(server: server, username: username, password: password)
            guard request == generation else { return }
            defaults.set(server, forKey: "previewServer")
            defaults.set(username, forKey: "previewUsername")
            await openLibraries()
        } catch {
            guard request == generation else { return }
            screen = .connection(Self.recovery(for: error))
        }
    }

    func openLibrariesForSelection() async {
        defaults.removeObject(forKey: "previewLibrary")
        await openLibraries()
    }

    func openLibraries() async {
        let request = generation
        screen = .loading
        do {
            let libraries = try await api.libraries()
            guard request == generation else { return }
            if let id = defaults.string(forKey: "previewLibrary"), let library = libraries.first(where: { $0.id == id }) {
                screen = .shelf(library)
            } else { screen = .libraries(libraries) }
        } catch {
            guard request == generation else { return }
            screen = .connection(Self.recovery(for: error))
        }
    }

    func select(_ library: Library) {
        defaults.set(library.id, forKey: "previewLibrary")
        screen = .shelf(library)
    }

    func signOut() {
        do {
            try api.signOut()
            generation = UUID()
            defaults.removeObject(forKey: "previewLibrary")
            screen = .connection(nil)
        } catch { screen = .connection(Self.recovery(for: error)) }
    }

    static func recovery(for error: Error) -> String {
        if let failure = error as? URLError {
            switch failure.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return "This server's certificate is not trusted. Check its date and hostname. For your homelab CA, install its profile and enable full trust in Settings → General → About → Certificate Trust Settings, then retry."
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
                return "The server could not be reached. Check its address, Wi-Fi or VPN, then retry. Your saved login is retained."
            default: return "The connection failed. Check the server address and network, then retry."
            }
        }
        if error as? APIError == .signInRequired { return "The server no longer accepts this login. Sign in again to continue." }
        return error.localizedDescription
    }
}
