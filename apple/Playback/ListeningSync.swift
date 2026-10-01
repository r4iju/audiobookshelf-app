import Foundation

@MainActor final class ListeningSync {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeListening/listening.json")
    }
    private let api: APIClient
    private let journal: ListeningJournal?
    private let loadingFailure: Error?
    private var request: Task<Void, Error>?

    init(api: APIClient) {
        self.api = api
        do {
            let journal = try ListeningJournal(file: Self.file)
            try journal.finishRecoveredSessions()
            self.journal = journal
            loadingFailure = nil
        } catch {
            journal = nil
            loadingFailure = error
        }
    }

    func begin(media: ListeningMedia, deviceID: String) async throws -> String {
        let account = try await api.currentAccount()
        return try loaded().begin(account: account, media: media, deviceID: deviceID)
    }

    func record(id: String, position: Double, listened: Double) throws {
        try loaded().record(id: id, position: position, listened: listened)
    }

    func finish(id: String) throws { try loaded().finish(id: id) }

    func flush() async throws {
        if let request { return try await request.value }
        let journal = try loaded()
        let account = try await api.currentAccount()
        let transfer = Task { @MainActor in
            while let next = journal.pending(account: account).first {
                try Task.checkCancellation()
                try await api.syncListening(next)
                try journal.acknowledge(next)
            }
        }
        request = transfer
        defer { request = nil }
        try await transfer.value
    }

    private func loaded() throws -> ListeningJournal {
        guard let journal else { throw loadingFailure ?? ListeningJournal.Failure.invalidData }
        return journal
    }
}
