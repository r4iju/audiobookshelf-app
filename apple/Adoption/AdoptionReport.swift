import Foundation

/// What one `NativeMigrationAdoption.apply` left in the native stores, and what it did not.
/// Only `.ready` downloads and `.adopted` reading positions are usable natively; everything else
/// is retained (in the migration outcome or the adoption ledger) and explained in `issues`.
struct AdoptionReport: Equatable {
    struct Download: Equatable {
        enum Status: String, Codable {
            /// In the native manifest with every part present: plays or opens offline.
            case ready
            /// In the native manifest with only some parts carried over; Retry fetches the rest.
            case partial
            /// Needs the signed-in account's server copy first (supplementary PDFs, downloads the
            /// upgrade interrupted); `sync()` completes it.
            case waitingForServer
            /// The native app already had this download; it was left as it is.
            case keptNative
            /// Adopted earlier, then removed in the native app; not added again.
            case removedByUser
            /// The native app is downloading this entry now; left to finish.
            case inProgress
            /// Only a format whose reader is deferred (MOBI, AZW3, CBZ, CBR); kept in the outcome.
            case deferredFormat
            /// No account or server item to attach it to; kept in the outcome.
            case unattached
            /// None of its files could be carried over; kept in the outcome.
            case unavailable
        }

        var account: MigrationAccount?
        var libraryItemID: String?
        var episodeID: String?
        /// Filename of a supplementary file this row stands for.
        var supplementaryFile: String?
        var title: String
        var status: Status
        var nativeEntryID: String?
        var adoptedParts: Int
        var totalParts: Int
        var message: String?
    }

    struct Reading: Equatable {
        enum Status: String, Codable {
            /// A native reader resumes at this location.
            case adopted
            /// The native app already had a newer location; it was left as it is.
            case keptNative
            /// A deferred reader's format; kept verbatim in the outcome.
            case deferredFormat
            /// The legacy value could not be interpreted; kept verbatim in the outcome.
            case invalid
            /// No account or server item to attach it to; kept in the outcome.
            case unattached
        }

        var account: MigrationAccount?
        var libraryItemID: String?
        var format: String?
        var location: String
        var status: Status
    }

    struct Settings: Equatable {
        /// Native keys written from legacy values because the native key was unset.
        var applied: [String] = []
        /// Native keys already set in this app; the legacy value was not used.
        var keptNative: [String] = []
        /// Legacy settings without a native equivalent; kept in the outcome.
        var retained: [String] = []
    }

    struct Listening: Equatable {
        var account: MigrationAccount
        /// Unsent legacy listening sessions waiting for this account's server.
        var pendingSessions: Int
        /// Sessions the server has accepted.
        var acknowledgedSessions: Int
        /// Legacy positions newer than the server's that still need to be sent.
        var pendingProgress: Int
        /// Sessions the server may or may not hold (an attempt got no answer, or the server's
        /// row has listening this device does not know about). Kept and not sent again.
        var unconfirmedSessions = 0
    }

    /// The account signed in when `apply` ran; only its downloads play or open now.
    var signedInAccount: MigrationAccount?
    var downloads: [Download] = []
    var reading: [Reading] = []
    var settings = Settings()
    var listening: [Listening] = []
    /// Unsent sessions and positions with no account to send them to; kept in the outcome.
    var unsendableSessions = 0
    var accountsRequiringSignIn: [MigratedAccount] = []
    /// The migration module's own issues, unchanged.
    var moduleIssues: [MigrationIssue] = []

    /// One paragraph separating what is usable now from what is retained, deferred, unresolved or
    /// still to be sent.
    var summary: String {
        func count(_ status: Download.Status) -> Int { downloads.filter { $0.status == status }.count }
        func phrase(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
        var sentences: [String] = []
        let usable = downloads.filter { $0.status == .ready && $0.account != nil && $0.account == signedInAccount }.count
        let later = count(.ready) - usable
        let partial = count(.partial), waiting = count(.waitingForServer)
        let deferred = count(.deferredFormat), unattached = count(.unattached), unavailable = count(.unavailable)
        if usable > 0 { sentences.append("\(phrase(usable, "download is", "downloads are")) ready to play or read offline.") }
        if later > 0 { sentences.append(later == 1 ? "1 download is ready once its account is signed in." : "\(later) downloads are ready once their accounts are signed in.") }
        if partial > 0 { sentences.append("\(phrase(partial, "download was", "downloads were")) carried over in part; Retry fetches the missing parts.") }
        if waiting > 0 { sentences.append("\(phrase(waiting, "download waits", "downloads wait")) for the server's copy before it can be added.") }
        if deferred > 0 { sentences.append("\(phrase(deferred, "file is", "files are")) kept in a format this app does not open yet.") }
        if unattached > 0 { sentences.append("\(phrase(unattached, "item is", "items are")) kept on this device without a server account to attach to.") }
        if unavailable > 0 { sentences.append("\(phrase(unavailable, "download", "downloads")) could not be carried over and must be downloaded again.") }
        let kept = count(.keptNative), removed = count(.removedByUser), downloading = count(.inProgress)
        if kept > 0 { sentences.append("\(phrase(kept, "download this app already had was", "downloads this app already had were")) kept.") }
        if removed > 0 { sentences.append("\(phrase(removed, "download removed in this app stays", "downloads removed in this app stay")) removed.") }
        if downloading > 0 { sentences.append("\(phrase(downloading, "download this app is fetching was", "downloads this app is fetching were")) left to finish.") }
        let adoptedReading = reading.filter { $0.status == .adopted }.count
        let unusedReading = reading.filter { [.deferredFormat, .invalid, .unattached].contains($0.status) }.count
        if adoptedReading > 0 { sentences.append("\(phrase(adoptedReading, "reading position was", "reading positions were")) carried over.") }
        if unusedReading > 0 { sentences.append("\(phrase(unusedReading, "reading position is", "reading positions are")) kept but not used.") }
        let sessions = listening.reduce(0) { $0 + $1.pendingSessions }, positions = listening.reduce(0) { $0 + $1.pendingProgress }
        if sessions > 0 { sentences.append("\(phrase(sessions, "listening session is", "listening sessions are")) waiting to be sent to the server.") }
        let unconfirmed = listening.reduce(0) { $0 + $1.unconfirmedSessions }
        if unconfirmed > 0 { sentences.append("\(phrase(unconfirmed, "listening session", "listening sessions")) could not be confirmed on the server and \(unconfirmed == 1 ? "is" : "are") kept on this device.") }
        if positions > 0 { sentences.append("\(phrase(positions, "listening position is", "listening positions are")) waiting to be compared with the server.") }
        if unsendableSessions > 0 { sentences.append("\(phrase(unsendableSessions, "listening record has", "listening records have")) no account to send it to and is kept.") }
        if !accountsRequiringSignIn.isEmpty { sentences.append("Sign in to \(phrase(accountsRequiringSignIn.count, "account", "accounts")) to use the rest of its data.") }
        if sentences.isEmpty { return "There was nothing to carry over." }
        return sentences.joined(separator: " ")
    }

    /// One plain-language line for every artifact that is not usable natively yet, then the
    /// module's issues.
    var issues: [String] {
        var lines: [String] = []
        for download in downloads where ![.ready, .keptNative, .removedByUser].contains(download.status) {
            let name = download.supplementaryFile.map { "\(download.title) (\($0))" } ?? download.title
            lines.append("\(name): " + (download.message ?? download.status.rawValue))
        }
        for position in reading {
            let name = position.libraryItemID ?? "A book"
            switch position.status {
            case .adopted, .keptNative: continue
            case .deferredFormat: lines.append("\(name): the reading position is kept for a reader this app does not have yet.")
            case .invalid: lines.append("\(name): the saved reading position could not be interpreted and is kept unchanged.")
            case .unattached: lines.append("\(name): the reading position has no server account and is kept.")
            }
        }
        for value in listening where value.pendingSessions > 0 || value.pendingProgress > 0 {
            lines.append("Listening for \(value.account.server) is waiting to be sent (\(value.pendingSessions) sessions, \(value.pendingProgress) positions).")
        }
        for value in listening where value.unconfirmedSessions > 0 {
            lines.append("Listening for \(value.account.server): \(value.unconfirmedSessions) \(value.unconfirmedSessions == 1 ? "session" : "sessions") could not be confirmed on the server. They are kept on this device and not sent again, so no listening is counted twice.")
        }
        return lines + moduleIssues.map(\.message)
    }
}

/// What one `NativeMigrationAdoption.sync()` sent for the signed-in account.
struct AdoptionSyncReport: Equatable {
    var account: MigrationAccount?
    var sessionsAcknowledged = 0
    var sessionsPending = 0
    /// Kept on this device because the server may or may not hold them; not sent again.
    var sessionsUnconfirmed = 0
    var progressSent = 0
    var progressPending = 0
    var downloadsCompleted = 0
    var failures: [String] = []
}
