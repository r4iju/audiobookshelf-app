import Foundation

/// An in-process Audiobookshelf-shaped server for one test. Requests never leave the process.
final class StubServer {
    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let body: Data?
        var json: [String: Any]? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
        var jsonArray: [Any]? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] } }
    }

    enum Response {
        case json(Int, Any)
        case status(Int)
        /// A file body with its content type.
        case file(Int, String, Data)
        /// A file body without Content-Length, as a proxy that streams the response sends it.
        case unsizedFile(Int, String, Data)
        /// The server handled the request but the client never saw the answer.
        case lost
        /// The loading system failed the request with this error.
        case failure(Error)
    }

    private let lock = NSLock()
    private var routes: [String: (Request) -> Response] = [:]
    private var recorded: [Request] = []

    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return recorded }

    func requests(_ method: String, _ path: String) -> [Request] {
        requests.filter { $0.method == method && $0.path == path }
    }

    /// `path` is matched exactly against the URL path (including the server's subpath).
    func route(_ method: String, _ path: String, _ handler: @escaping (Request) -> Response) {
        lock.lock(); routes[method + " " + path] = handler; lock.unlock()
    }

    fileprivate func handle(_ request: URLRequest) -> Response {
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        let recordedRequest = Request(method: request.httpMethod ?? "GET", path: url.path, query: query, body: body)
        lock.lock()
        recorded.append(recordedRequest)
        let handler = routes[recordedRequest.method + " " + recordedRequest.path]
        lock.unlock()
        return handler?(recordedRequest) ?? .status(404)
    }

    func session() -> URLSession {
        StubProtocol.server = self
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class StubProtocol: URLProtocol {
    static var server: StubServer?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server else { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        switch server.handle(request) {
        case .lost:
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .status(let code):
            respond(code, Data())
        case .json(let code, let value):
            respond(code, try! JSONSerialization.data(withJSONObject: value))
        case .file(let code, let type, let data):
            respond(code, data, headers: ["Content-Type": type, "Content-Length": String(data.count)])
        case .unsizedFile(let code, let type, let data):
            respond(code, data, headers: ["Content-Type": type])
        }
    }

    private func respond(_ code: Int, _ data: Data, headers: [String: String] = ["Content-Type": "application/json"]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
