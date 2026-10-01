import XCTest

/// The waiting-save notice of book details, refreshed while account lookups are still running.
@MainActor final class WaitingWritesTests: XCTestCase {
    private let server = "https://books.example.test/abs"
    private let stub = StubServer()
    private let credentials = MemoryCredentials()
    private var folder: URL!
    private var ledger: PublicationLedger!
    /// The first account lookup waits for this.
    private let gate = DispatchSemaphore(value: 0)
    private var alice: AccountIdentity!
    private var bob: AccountIdentity!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ledger = PublicationLedger(file: folder.appendingPathComponent("publications.json"))
        alice = try AccountIdentity(server: server, userID: "user-1")
        bob = try AccountIdentity(server: server, userID: "user-2")
        var lookups = 0
        let gate = gate
        stub.route("GET", "/abs/api/me") { _ in
            lookups += 1
            return lookups == 1 ? .held(gate, .json(200, StubUser.json(id: "user-1"))) : .json(200, StubUser.json(id: "user-1"))
        }
    }

    override func tearDown() async throws {
        gate.signal()
        StubProtocol.server = nil
        try? FileManager.default.removeItem(at: folder)
    }

    /// Signed in as alice by credentials saved before user ids were kept, so finding the account asks the server.
    private func client(userID: String?) -> APIClient {
        credentials.value = Credentials(server: server, accessToken: "SYNTHETIC", refreshToken: nil, userID: userID, username: userID)
        return APIClient(store: credentials, session: stub.session())
    }

    private func hold(_ account: AccountIdentity, itemID: String = "book-0") throws {
        try ledger.issue(PublicationLedger.Write(id: UUID(), account: account, itemID: itemID, episodeID: nil, method: "POST", path: "/abs/api/session/local-all",
                                                 body: Data("{}".utf8), issuedAt: Date().timeIntervalSince1970 * 1_000))
    }

    /// Starts a refresh and returns once its account lookup reached the server.
    private func started(_ refresh: @escaping () async -> Void) async throws -> Task<Void, Never> {
        let task = Task { await refresh() }
        for _ in 0..<200 where stub.requests("GET", "/abs/api/me").isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(stub.requests("GET", "/abs/api/me").count, 1, "Precondition: the lookup is running")
        return task
    }

    func testALookupThatFailsAfterAnotherSignInLeavesTheNewerAnswer() async throws {
        let api = client(userID: nil)
        let writes = WaitingWrites()
        try hold(bob)
        let stale = try await started { await writes.refresh(api: api, ledger: self.ledger, owner: self.bob, itemID: "book-0", episodeID: nil) }
        credentials.value = Credentials(server: server, accessToken: "SYNTHETIC-2", refreshToken: nil, userID: "user-2", username: "user-2")
        try api.restoreSavedCredentials()
        await writes.refresh(api: api, ledger: ledger, owner: bob, itemID: "book-0", episodeID: nil)
        XCTAssertTrue(writes.waiting, "Precondition: bob's save is waiting")
        gate.signal()
        await stale.value
        XCTAssertTrue(writes.waiting, "The lookup for the earlier sign-in must not clear the newer answer")
    }

    func testALookupForAnEarlierTitleLeavesTheAnswerForTheShownOne() async throws {
        let api = client(userID: nil)
        let writes = WaitingWrites()
        try hold(alice, itemID: "book-0")
        let stale = try await started { await writes.refresh(api: api, ledger: self.ledger, owner: self.alice, itemID: "book-0", episodeID: nil) }
        await writes.refresh(api: api, ledger: ledger, owner: alice, itemID: "book-1", episodeID: nil)
        gate.signal()
        await stale.value
        XCTAssertFalse(writes.waiting, "Nothing waits for the title shown now")
    }

    func testALookupThatEndsAfterTheDetailsLeftPublishesNothing() async throws {
        let api = client(userID: nil)
        let writes = WaitingWrites()
        try hold(alice)
        let stale = try await started { await writes.refresh(api: api, ledger: self.ledger, owner: self.alice, itemID: "book-0", episodeID: nil) }
        writes.stop()
        gate.signal()
        await stale.value
        XCTAssertFalse(writes.waiting, "Details that left must not change")
    }

    func testDetailsOpenedForAnotherAccountShowNothingOfTheSignedInOne() async throws {
        let api = client(userID: "user-2")
        let writes = WaitingWrites()
        try hold(bob)
        await writes.refresh(api: api, ledger: ledger, owner: alice, itemID: "book-0", episodeID: nil)
        XCTAssertFalse(writes.waiting, "Bob's waiting save is not alice's")
    }
}
