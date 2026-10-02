import TVCore
import UIKit
import XCTest
@testable import YearExport

/// Runs the production cover path (APIClient plus the loader) while the signed-in account changes.
@MainActor final class YearExportPinnedArtworkTests: XCTestCase {
    override func tearDown() {
        GatedURLProtocol.reset()
        super.tearDown()
    }

    func testAccountSwitchAToBToAWhileCoversLoadAbortsWithoutRequestingUnderAnotherSession() async throws {
        let store = Store()
        store.value = Credentials(server: "https://books.example", accessToken: "token-a", refreshToken: nil, userID: "alice")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedURLProtocol.self]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel() }
        let api = APIClient(store: store, session: http)
        let firstBatch = Gate(), lastCover = Gate()
        GatedURLProtocol.respond = { token, item in
            switch (token, item) {
            case ("token-a", _): return (firstBatch, 404, Data())   // alice's first covers fail while the account changes
            case ("token-b", "s4"): return (nil, 200, YearExportArtworkTests.cover(.red))
            case ("token-b", _): return (lastCover, 404, Data())
            default: return (nil, 404, Data())
            }
        }
        let pinned = api.authorizationRevision
        let load = Task { try await YearExportArtworkLoader.load(year: 2025, primary: [], secondary: (0..<6).map { "s\($0)" }, api: api, authorization: pinned) }
        try await wait { GatedURLProtocol.sent.count >= YearExportArtworkLoader.concurrentRequests }

        try api.completeBrowserLogin(server: "https://books.example", response: Self.login("bob", token: "token-b"))
        firstBatch.open()
        var finished = false
        let watcher = Task { _ = try? await load.value; finished = true }
        try await wait { finished || GatedURLProtocol.sent.contains { $0.item == "s5" } }
        try api.completeBrowserLogin(server: "https://books.example", response: Self.login("alice", token: "token-a2"))
        lastCover.open()

        do {
            let artwork = try await load.value
            XCTFail("Loaded \(artwork.secondary.count) covers across an account switch")
        } catch {
            XCTAssertEqual(error as? YearExportArtworkError, .accountChanged, "\(error)")
        }
        _ = await watcher.value
        let foreign = GatedURLProtocol.sent.filter { $0.token != "token-a" }
        XCTAssertEqual(foreign.map(\.item), [], "covers requested with another session: \(foreign)")
    }

    func testAnAccountChangeReportedByAFetchIsNotTreatedAsAMissingCover() async {
        do {
            let artwork = try await YearExportArtworkLoader.load(year: 2025, primary: ["a", "b"], secondary: [], owner: 1, currentAccount: { 1 }) { id in
                if id == "a" { throw YearExportArtworkError.accountChanged }
                return YearExportArtworkTests.cover(.red)
            }
            XCTFail("Returned \(artwork.primary.count) covers after a fetch reported an account change")
        } catch {
            XCTAssertEqual(error as? YearExportArtworkError, .accountChanged)
        }
    }

    private static func login(_ user: String, token: String) -> Data {
        Data(#"{"user":{"id":"\#(user)","username":"\#(user)","accessToken":"\#(token)"}}"#.utf8)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    }
}

@MainActor private final class Store: CredentialStore {
    var value: Credentials?
    func load() throws -> Credentials? { value }
    func save(_ credentials: Credentials) throws { value = credentials }
    func clear() throws { value = nil }
}

final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { semaphore.wait() }
    func open() { for _ in 0..<64 { semaphore.signal() } }
}

/// Answers cover requests, optionally holding them until a gate opens, and records each request's session.
final class GatedURLProtocol: URLProtocol {
    struct Sent { let token: String; let item: String }
    private static let lock = NSLock()
    private static var log: [Sent] = []
    static var respond: ((String, String) -> (Gate?, Int, Data))?
    static var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return log }
    static func reset() { lock.lock(); log = []; respond = nil; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let parts = request.url?.pathComponents ?? []
        let item = parts.count >= 2 ? parts[parts.count - 2] : ""
        Self.lock.lock(); Self.log.append(Sent(token: token, item: item)); let respond = Self.respond; Self.lock.unlock()
        guard let url = request.url, let (gate, status, body) = respond?(token, item) else { return }
        DispatchQueue.global().async { [weak self] in
            gate?.wait()
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
