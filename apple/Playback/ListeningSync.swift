import Foundation

@MainActor final class ListeningSync {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeListening/listening.json")
    }
    private let api: APIClient
    private let journal: ListeningJournal?
    private let loadingFailure: Error?
    private struct Transfer {
        let id: UUID
        let task: Task<Void, Error>
    }
    private var request: Transfer?

    init(api: APIClient) {
        self.api = api
        do {
            #if os(tvOS)
            let journal = try ListeningJournal(file: Self.file, persistentDefaults: .standard)
            #else
            let journal = try ListeningJournal(file: Self.file)
            #endif
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

    func beginOffline(_ audio: OfflineAudio, position: Double, deviceID: String) throws -> String {
        let media = ListeningMedia(itemID: audio.media.libraryItemID, episodeID: audio.media.episodeID, title: audio.media.title, author: audio.media.author, mediaType: audio.media.mediaType, duration: audio.media.duration, startTime: position)
        return try loaded().begin(account: audio.account, media: media, deviceID: deviceID)
    }

    func position(for audio: OfflineAudio) throws -> Double {
        try loaded().cachedPosition(account: audio.account, itemID: audio.media.libraryItemID, episodeID: audio.media.episodeID, newerThan: audio.serverUpdatedAt) ?? audio.serverPosition
    }

    func hasFinished(_ audio: OfflineAudio, serverFinished: Bool) throws -> Bool {
        if let newer = try loaded().cachedPosition(account: audio.account, itemID: audio.media.libraryItemID, episodeID: audio.media.episodeID, newerThan: audio.serverUpdatedAt.nextUp) {
            return newer >= audio.media.duration
        }
        return serverFinished || audio.serverPosition >= audio.media.duration
    }

    /// Whether this device still holds unacknowledged listening for the media or, given a remote
    /// update time, saved a later position for it.
    func hasLocalListening(account: AccountIdentity, itemID: String, episodeID: String?, newerThan remoteUpdatedAt: Double?) throws -> Bool {
        let journal = try loaded()
        if journal.pending(account: account).contains(where: { $0.media.libraryItemID == itemID && $0.media.episodeID == episodeID }) { return true }
        guard let remoteUpdatedAt else { return false }
        return journal.cachedPosition(account: account, itemID: itemID, episodeID: episodeID, newerThan: remoteUpdatedAt.nextUp) != nil
    }

    func record(id: String, position: Double, listened: Double) throws {
        try loaded().record(id: id, position: position, listened: listened)
    }

    func finish(id: String) throws { try loaded().finish(id: id) }

    func flush() async throws {
        if let request { return try await request.task.value }
        try Task.checkCancellation()
        let journal = try loaded()
        let account = try await api.currentAccount()
        let transfer = Task { @MainActor in
            while let next = journal.pending(account: account).first {
                try Task.checkCancellation()
                try await api.syncListening(next)
                try journal.acknowledge(next)
            }
            let user = try await api.me()
            guard try await api.currentAccount() == account else { throw CancellationError() }
            try rememberRemoteProgress(user, account: account)
        }
        let id = UUID()
        request = Transfer(id: id, task: transfer)
        defer { if request?.id == id { request = nil } }
        try await transfer.value
    }

    func rememberRemoteProgress(_ user: CurrentUser, account: AccountIdentity) throws {
        let journal = try loaded()
        for progress in user.mediaProgress {
            guard let position = progress.currentTime, let updated = progress.lastUpdate else { continue }
            try journal.rememberRemotePosition(account: account, itemID: progress.libraryItemId, episodeID: progress.episodeId, time: position, updatedAt: updated)
        }
    }

    func cancelTransfers() async {
        guard let current = request else { return }
        request = nil
        current.task.cancel()
        _ = try? await current.task.value
    }

    private func loaded() throws -> ListeningJournal {
        guard let journal else { throw loadingFailure ?? ListeningJournal.Failure.invalidData }
        return journal
    }
}
