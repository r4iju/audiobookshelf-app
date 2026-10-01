import Foundation

public struct ServerEvent {
    public let name: String
    public let data: Data
}

@MainActor public final class ServerEvents {
    private let api: APIClient
    private var socket: URLSessionWebSocketTask?
    private var watchdog: Task<Void, Never>?
    private var stopped = false
    private var lastMessage = Date()
    private var heartbeatLimit: TimeInterval = 30
    private var authenticated = false
    public init(api: APIClient) { self.api = api }
    public func stop() {
        stopped = true
        watchdog?.cancel(); watchdog = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
    public func listen(account: AccountIdentity, onEvent: (ServerEvent) -> Void, onFailure: (Error) -> Void) async {
        var delay: UInt64 = 1
        defer { stop() }
        while !stopped, !Task.isCancelled {
            do {
                guard try await api.currentAccount() == account else { throw APIError.signInRequired }
                let token = try await api.validToken()
                guard !stopped, !Task.isCancelled, try await api.currentAccount() == account else { throw APIError.signInRequired }
                var components = URLComponents(url: try ServerAddress(account.server).url(path: "socket.io/", query: [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]), resolvingAgainstBaseURL: false)!
                components.path += "/"
                components.scheme = components.scheme == "https" ? "wss" : "ws"
                guard let url = components.url else { throw APIError.invalidServer }
                var request = URLRequest(url: url); request.timeoutInterval = 60
                let connection = URLSession.shared.webSocketTask(with: request)
                socket = connection; authenticated = false; lastMessage = Date(); heartbeatLimit = 30
                connection.resume()
                let started = Date()
                watchdog = Task { [weak self, weak connection] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                        guard let self, let connection else { return }
                        if Date().timeIntervalSince(self.lastMessage) > self.heartbeatLimit || !self.authenticated && Date().timeIntervalSince(started) > 15 {
                            connection.cancel(with: .goingAway, reason: nil); return
                        }
                    }
                }
                while !stopped, !Task.isCancelled {
                    let message = try await receive(connection)
                    guard !stopped, !Task.isCancelled, try await api.currentAccount() == account else { throw APIError.signInRequired }
                    lastMessage = Date()
                    guard case .string(let packet) = message else { continue }
                    if packet.hasPrefix("0") {
                        let opening = try JSONDecoder().decode(Opening.self, from: Data(packet.dropFirst().utf8))
                        guard opening.pingInterval > 0, opening.pingTimeout > 0 else { throw APIError.invalidServer }
                        heartbeatLimit = (opening.pingInterval + opening.pingTimeout) / 1000
                        try await send("40", connection)
                    } else if packet.hasPrefix("2") { try await send("3" + packet.dropFirst(), connection) }
                    else if packet.hasPrefix("40") {
                        let data = try JSONSerialization.data(withJSONObject: ["auth", token])
                        try await send("42" + String(decoding: data, as: UTF8.self), connection)
                    } else if packet.hasPrefix("42") {
                        guard let values = try JSONSerialization.jsonObject(with: Data(packet.dropFirst(2).utf8)) as? [Any], values.count == 2, let name = values[0] as? String else { continue }
                        if name == "auth_failed" { throw APIError.signInRequired }
                        if name == "init" {
                            guard let payload = values[1] as? [String: Any], payload["userId"] as? String == account.userID else { throw APIError.signInRequired }
                            authenticated = true; delay = 1
                        }
                        guard authenticated, JSONSerialization.isValidJSONObject(values[1]) else { continue }
                        onEvent(ServerEvent(name: name, data: try JSONSerialization.data(withJSONObject: values[1])))
                    } else if packet == "1" || packet == "41" { throw URLError(.networkConnectionLost) }
                }
            } catch {
                if stopped || Task.isCancelled { return }
                watchdog?.cancel(); watchdog = nil
                socket?.cancel(with: .goingAway, reason: nil); socket = nil
                if error as? APIError == .signInRequired { onFailure(error); return }
                onFailure(error)
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
                delay = min(delay * 2, 15)
            }
        }
    }
    private struct Opening: Decodable { let pingInterval: Double; let pingTimeout: Double }
    private func receive(_ connection: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive { continuation.resume(with: $0) }
        }
    }
    private func send(_ text: String, _ connection: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(.string(text)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
