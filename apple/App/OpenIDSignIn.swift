import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor final class OpenIDSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callback = "audiobookshelf-native-preview://oauth"
    private var browser: ASWebAuthenticationSession?
    private var browserID: UUID?

    enum Failure: LocalizedError {
        case canceled, invalidResponse, cannotPresent, randomness, notEnabled
        var errorDescription: String? {
            switch self {
            case .canceled: return NativeStrings.current("Browser sign-in was canceled. Your saved account is retained.")
            case .invalidResponse: return NativeStrings.current("The browser sign-in response could not be verified. Retry sign-in and check the server's OpenID redirects.")
            case .cannotPresent: return NativeStrings.current("The sign-in browser could not open. Return to the app and try again.")
            case .randomness: return NativeStrings.current("Secure sign-in could not be prepared. Try again.")
            case .notEnabled: return NativeStrings.current("OpenID sign-in is not enabled on this server. Use your username and password.")
            }
        }
    }

    func signIn(server: String) async throws -> Data {
        let address = try ServerAddress(server)
        let verifier = try randomValue()
        let state = try randomValue()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirects = StopRedirects()
        let transport = URLSession(configuration: .ephemeral, delegate: redirects, delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        var statusRequest = URLRequest(url: try address.url(path: "status"))
        statusRequest.timeoutInterval = 25
        let (statusData, statusResponse) = try await transport.data(for: statusRequest)
        guard let statusResponse = statusResponse as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard statusResponse.statusCode == 200 else { throw APIError.http(statusResponse.statusCode) }
        struct Status: Decodable { let authMethods: [String]? }
        let status = try JSONDecoder().decode(Status.self, from: statusData)
        guard status.authMethods?.contains("openid") == true else { throw Failure.notEnabled }
        var request = URLRequest(url: try address.url(path: "auth/openid", query: [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: Self.callback),
            URLQueryItem(name: "client_id", value: "Audiobookshelf-App"),
            URLQueryItem(name: "response_type", value: "code")
        ]))
        request.timeoutInterval = 25
        let (_, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (300..<400).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let provider = URL(string: location, relativeTo: request.url)?.absoluteURL else {
            if response.statusCode >= 400 { throw APIError.http(response.statusCode) }
            throw Failure.invalidResponse
        }
        let providerParts = try validatedProvider(provider)
        let providerState = try Self.single("state", in: providerParts)
        guard providerState == state,
              try Self.single("code_challenge", in: providerParts) == challenge,
              try Self.single("code_challenge_method", in: providerParts) == "S256" else { throw Failure.invalidResponse }
        let result = try await openBrowser(provider)
        guard let callback = URLComponents(url: result, resolvingAgainstBaseURL: false),
              callback.scheme == "audiobookshelf-native-preview", callback.host == "oauth",
              callback.path.isEmpty, callback.user == nil, callback.password == nil,
              callback.port == nil, callback.fragment == nil,
              try Self.single("state", in: callback) == providerState else { throw Failure.invalidResponse }
        let code = try Self.single("code", in: callback)
        var exchange = URLRequest(url: try address.url(path: "auth/openid/callback", query: [
            URLQueryItem(name: "state", value: providerState),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]))
        exchange.setValue("true", forHTTPHeaderField: "x-return-tokens")
        exchange.timeoutInterval = 25
        let (data, exchanged) = try await transport.data(for: exchange)
        guard let exchanged = exchanged as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard exchanged.statusCode == 200 else { throw APIError.http(exchanged.statusCode) }
        return data
    }

    private func validatedProvider(_ url: URL) throws -> URLComponents {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let host = parts.host, !host.isEmpty,
              parts.scheme == "https" || parts.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host) else { throw Failure.invalidResponse }
        _ = try Self.single("client_id", in: parts)
        _ = try Self.single("redirect_uri", in: parts)
        guard try Self.single("scope", in: parts).split(separator: " ").contains("openid") else { throw Failure.invalidResponse }
        return parts
    }

    private static func single(_ name: String, in parts: URLComponents) throws -> String {
        var query = parts
        query.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        let matches = query.queryItems?.filter { $0.name == name } ?? []
        guard matches.count == 1, let value = matches.first?.value, !value.isEmpty else { throw Failure.invalidResponse }
        return value
    }

    private func openBrowser(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { completion in
            let id = UUID()
            browserID = id
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "audiobookshelf-native-preview") { [weak self] callback, error in
                Task { @MainActor in
                    guard let self, self.browserID == id else { return }
                    self.browserID = nil
                    self.browser = nil
                    if let callback { completion.resume(returning: callback) }
                    else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { completion.resume(throwing: Failure.canceled) }
                    else { completion.resume(throwing: error ?? Failure.invalidResponse) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            if !session.start() { browserID = nil; browser = nil; completion.resume(throwing: Failure.cannotPresent) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.randomness }
        return Self.base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private final class StopRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
