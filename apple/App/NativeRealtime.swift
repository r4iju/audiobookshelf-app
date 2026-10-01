import Foundation
import Combine

/// Owns the one authenticated realtime stream of the signed-in account and republishes its changes to visible screens.
@MainActor final class NativeRealtime: ObservableObject {
    struct Event {
        let account: AccountIdentity
        let change: RealtimeChange
    }
    private struct SignIn: Equatable {
        let account: AccountIdentity
        let authorization: UUID
    }
    /// Sent only while `account` and its sign-in are still current, so a subscriber never sees a previous account's change.
    let events = PassthroughSubject<Event, Never>()
    /// The server rejected the stream's credentials for this account; `connect()` retries once the account is current again.
    let signInRejected = PassthroughSubject<AccountIdentity, Never>()
    private let api: APIClient
    private let localSession: () -> String?
    private var stream: ServerEvents?
    private var task: Task<Void, Never>?
    private var pinned: SignIn?
    private var generation = UUID()
    private var authenticated = false

    /// `localSession` names this device's playback session. The server echoes each of its syncs (every 15 seconds while
    /// playing) as a progress event, which carries nothing the device does not already know.
    init(api: APIClient, localSession: @escaping () -> String?) { self.api = api; self.localSession = localSession }

    private var current: SignIn? {
        guard let credentials = api.credentials, let user = credentials.userID, let account = try? AccountIdentity(server: credentials.server, userID: user) else { return nil }
        return SignIn(account: account, authorization: api.authorizationRevision)
    }

    /// Follows the current sign-in: keeps a live stream, replaces one opened for another account or sign-in, or stops.
    func connect() {
        let target = current
        guard target != pinned || task == nil else { return }
        // Restarting an ended stream of the same sign-in may have missed changes, like any reconnection.
        let resuming = target == pinned && authenticated
        stop()
        guard let target else { return }
        let request = UUID()
        let stream = ServerEvents(api: api)
        generation = request; pinned = target; self.stream = stream; authenticated = resuming
        task = Task { [weak self] in
            await stream.listen(account: target.account, onEvent: { event in
                guard let self, self.generation == request, self.current == target,
                      let change = RealtimeChange(event, owner: target.account, resumed: self.authenticated) else { return }
                if case .authenticated = change { self.authenticated = true }
                if case .progress(_, _, let session?) = change, session == self.localSession() { return }
                self.events.send(Event(account: target.account, change: change))
            }, onFailure: { failure in
                guard let self, self.generation == request, self.current == target, failure as? APIError == .signInRequired else { return }
                self.signInRejected.send(target.account)
            })
            guard let self, self.generation == request else { return }
            self.task = nil; self.stream = nil
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); stream?.stop()
        task = nil; stream = nil; pinned = nil; authenticated = false
    }
}
