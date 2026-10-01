import Foundation

/// Whether the server may still apply an earlier save of the title that book details show, so newer ones wait.
@MainActor final class WaitingWrites: ObservableObject {
    @Published private(set) var waiting = false

    /// `owner` is the account the details were opened for.
    func refresh(api: APIClient, ledger: PublicationLedger, owner: AccountIdentity?, itemID: String, episodeID: String?) async {
        guard let account = try? await api.currentAccount() else { waiting = false; return }
        waiting = ledger.unresolved(account: account, itemID: itemID, episodeID: episodeID)
    }

    /// The details are gone.
    func stop() {}
}
