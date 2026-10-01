import Foundation

/// Whether the server may still apply an earlier save of the title that book details show, so newer ones wait.
@MainActor final class WaitingWrites: ObservableObject {
    @Published private(set) var waiting = false
    /// The latest refresh. An earlier one publishes nothing.
    private var generation = UUID()
    /// The current appearance of the details, nil while they are gone. A refresh is scheduled with the one it
    /// was asked for in.
    private(set) var lifecycle: UUID?

    /// The details appeared.
    func activate() { lifecycle = UUID() }

    /// `owner` is the account the details were opened for. The answer is published only while this is the latest
    /// refresh and the sign-in it started under, of that account, is still current: a lookup can end after another
    /// sign-in, even a new one of the same account, or after the details moved on. A refresh asked for in an
    /// appearance that ended neither starts nor publishes, even once the details appear again.
    func refresh(api: APIClient, ledger: PublicationLedger, owner: AccountIdentity?, itemID: String, episodeID: String?, during appearance: UUID?) async {
        guard let appearance, appearance == lifecycle else { return }
        let request = UUID()
        generation = request
        let signIn = api.authorizationRevision
        let account = try? await api.currentAccount()
        guard generation == request, lifecycle == appearance, api.authorizationRevision == signIn else { return }
        guard let account else {
            // Signed out shows nothing; a lookup that merely failed leaves the last answer.
            if api.credentials == nil { waiting = false }
            return
        }
        guard account == owner, api.signIn?.account == account else { waiting = false; return }
        waiting = ledger.unresolved(account: account, itemID: itemID, episodeID: episodeID)
    }

    /// The details are gone.
    func stop() {
        lifecycle = nil
        generation = UUID()
    }
}
