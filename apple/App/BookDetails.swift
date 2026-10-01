import SwiftUI
import UIKit

struct BookDetails: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var serverQueue: NativePodcastQueue
    @EnvironmentObject private var readingStore: ReadingStore
    @State private var reader: ReadingSource?
    @EnvironmentObject private var localDownloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var migration: NativeMigrationStore
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var realtime: NativeRealtime
    let item: LibraryItem
    let catalog: CatalogStore
    let progress: MediaProgress?
    let episode: Episode?
    @State private var expanded: LibraryItem?
    private enum DetailFailure {
        /// `unresolvedWrites`: the discard waits for the owner to confirm a server restart.
        case load(String), discard(String), unresolvedWrites(String)
        var message: String {
            switch self { case .load(let message), .discard(let message), .unresolvedWrites(let message): return message }
        }
    }
    @State private var error: DetailFailure?
    @State private var request: Task<Void, Never>?
    @State private var playAttempted = false
    @State private var mediaProgress: [MediaProgress] = []
    @AppStorage("previewEpisodeSort") private var episodeSort = "publishedAt"
    @AppStorage("previewEpisodeDescending") private var episodeDescending = true
    @State private var episodeFilter = "all"
    private enum ProgressConfirmation: String, Identifiable {
        case finish, discard, serverRestarted
        var id: String { rawValue }
    }
    @State private var progressConfirmation: ProgressConfirmation?
    /// Whether the server may still apply an earlier save of this title, so newer ones wait.
    @State private var writesWaiting = false
    /// Whether confirming the restart goes on to discard the progress.
    @State private var restartThenDiscard = true
    @State private var progressDiscarded = false
    @State private var progressBusy = false
    @State private var progressRequest: Task<Void, Never>?
    @State private var canManagePodcasts = false
    @State private var showingFeed = false
    @State private var downloads: [PodcastDownload] = []
    @State private var downloadRequest: Task<Void, Never>?
    private var requestedDownloads: Set<String> { serverQueue.pending(itemID: item.id) }
    @State private var detailRevision = UUID()
    private var book: LibraryItem { expanded ?? item }

    init(item: LibraryItem, catalog: CatalogStore, progress: MediaProgress?, episode: Episode? = nil) {
        self.item = item; self.catalog = catalog; self.progress = progress; self.episode = episode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if book.mediaType != "podcast" || episode != nil {
                Button { NativeHaptic.impact("play"); playAttempted = true; Task { await player.start(item: book, episode: episode) } } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(l10n((selectedProgress?.currentTime ?? 0) > 0 ? "Resume listening" : episode != nil ? "Start episode" : "Start listening")).fontWeight(.semibold)
                        Spacer()
                    }.padding(18).foregroundColor(.white).background(ShelfStyle.accentFill).cornerRadius(16)
                }.disabled(player.preparing || progressBusy).accessibilityIdentifier("play-book")
                }
                if episode != nil || book.mediaType == "book" {
                    Button(l10n(selectedProgress?.isFinished == true ? "Mark unfinished" : "Mark finished"), action: toggleFinished).disabled(progressBusy)
                    if let progress = selectedProgress, (progress.progress ?? 0) > 0 || (progress.ebookProgress ?? 0) > 0 {
                        Button(l10n("Discard progress")) { NativeHaptic.impact("discard-progress"); progressConfirmation = .discard }
                            .disabled(progressBusy).accessibilityIdentifier("discard-progress")

                    }
                    if progressBusy { ProgressView(l10n("Saving your progress…")) }
                    if writesWaiting {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(l10n("An earlier save of this title's progress got no answer, and the server may still apply it over anything newer. Newer progress is kept on this device and sent once a server restart is confirmed.")).font(.callout).foregroundColor(.secondary)
                            Button(l10n("Restart the server")) { askForRestart(thenDiscard: false) }.disabled(progressBusy).accessibilityIdentifier("restart-server")
                        }
                    }
                }
                if let error = player.error, player.itemID == book.id || playAttempted { Text(error).font(.callout).foregroundColor(.red) }
                if let ebook = book.media.ebookFile, ["pdf", "epub"].contains(ebook.format), episode == nil {
                    Button(l10n("Read {0}", ebook.format.uppercased())) {
                        Task {
                            do { reader = ReadingSource(account: try await catalog.api.currentAccount(), itemID: book.id, title: book.title, ebook: ebook, file: nil) }
                            catch { recordLoadFailure(error.localizedDescription) }
                        }
                    }
                }
                if episode == nil {
                    ForEach(book.supplementaryEbooks.filter { ["pdf", "epub"].contains($0.ebook?.format ?? "") }) { file in
                        if let ebook = file.ebook {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(l10n("Read {0}", file.metadata?.filename ?? l10n("supplementary PDF"))) {
                                    Task {
                                        do { reader = ReadingSource(account: try await catalog.api.currentAccount(), itemID: book.id, title: file.metadata?.filename ?? book.title, ebook: ebook, file: nil, fileID: file.ino) }
                                        catch { recordLoadFailure(error.localizedDescription) }
                                    }
                                }
                                Button(l10n("Download {0}", file.metadata?.filename ?? l10n("supplementary PDF"))) { NativeHaptic.impact("download"); Task { await localDownloads.enqueue(item: book, episode: nil, supplementaryID: file.ino) } }
                            }
                        }
                    }
                }
                if book.mediaType == "book" || episode != nil {
                    Button(l10n("Download for offline")) { NativeHaptic.impact("download"); Task { await localDownloads.enqueue(item: book, episode: episode) } }
                    if let error = localDownloads.error { Text(error).foregroundColor(.red) }
                }
                if episode == nil { ItemServerActionsSection(itemID: book.id, catalog: catalog) }
                if let progress = selectedProgress, (progress.currentTime ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress.fraction).accentColor(ShelfStyle.accent)
                        Text(l10n("{0} listened · {1}% complete", ShelfTime.describe(progress.currentTime ?? 0), Int(progress.fraction * 100))).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                    }
                }
                if let description = episode?.description ?? book.media.metadata.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n(episode != nil ? "About this episode" : book.mediaType == "podcast" ? "About this podcast" : "About this book")).font(.title3.bold())
                        Text(Self.plainDescription(description)).font(.body).lineSpacing(5).foregroundColor(ShelfStyle.secondaryText)
                    }
                }
                if book.mediaType == "podcast", episode == nil {
                    podcastEpisodes
                }
                if let chapters = book.media.chapters, !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n("Chapters")).font(.title3.bold())
                        ForEach(chapters) { chapter in
                            HStack(alignment: .top) {
                                Text(chapter.title).font(.body)
                                Spacer()
                                Text(ShelfTime.describe(chapter.end - chapter.start)).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                if let error {
                    RecoveryCard(message: error.message) {
                        switch error {
                        case .load: load(monitorDownloads: true)
                        case .discard: discardProgress()
                        case .unresolvedWrites: askForRestart(thenDiscard: true)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(appearance.background).navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { load(monitorDownloads: true) }
            .onDisappear { request?.cancel(); progressRequest?.cancel(); downloadRequest?.cancel() }
            .sheet(isPresented: $showingFeed) {
                FeedEpisodes(api: catalog.api, item: book, presented: $showingFeed) { change in
                    switch change {
                    case .requested(let episodes): try serverQueue.begin(itemID: item.id, episodes: episodes)
                    case .accepted: watchDownloads()
                    case .rejected(let episodes): try serverQueue.reject(itemID: item.id, episodes: episodes)
                    }
                }
            }
            .fullScreenCover(item: $reader) { source in EbookReader(source: source, api: catalog.api, store: readingStore) }
            .alert(item: $progressConfirmation) { confirmation in
                switch confirmation {
                case .finish:
                    return Alert(title: Text(l10n("Mark book finished?")), message: Text(l10n("Your saved progress will change when this book is marked finished.")), primaryButton: .default(Text(l10n("Mark finished"))) { applyFinished(true) }, secondaryButton: .cancel(Text(l10n("Cancel"))))
                case .discard:
                    return Alert(title: Text(l10n("Confirm")), message: Text(l10n("Are you sure you want to reset your progress?")), primaryButton: .destructive(Text(l10n("Discard progress")), action: discardProgress), secondaryButton: .cancel(Text(l10n("Cancel"))))
                case .serverRestarted:
                    return Alert(title: Text(l10n("Restart the server now")), message: Text(l10n("Restart the Audiobookshelf server now, and confirm once it is running again. A restart before this message does not count, because the save that got no answer may have reached the server after it.")), primaryButton: .destructive(Text(l10n("Server restarted")), action: confirmRestart), secondaryButton: .cancel(Text(l10n("Cancel"))))
                }
            }
            .onChange(of: serverQueue.revision) { _ in if book.mediaType == "podcast", episode == nil, canManagePodcasts { watchDownloads() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in load(monitorDownloads: true) }
            .onReceive(realtime.events) { event in receive(event) }
    }

    @ViewBuilder private var header: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 28) {
                BookArtwork(item: book, catalog: catalog).frame(width: 200)
                metadata(alignment: .leading)
            }
        } else {
            VStack(spacing: 20) {
                BookArtwork(item: book, catalog: catalog).frame(width: 184)
                metadata(alignment: .center)
            }.frame(maxWidth: .infinity)
        }
    }
    private func metadata(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(episode?.title ?? book.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if episode != nil { Text(book.title).font(.subheadline).foregroundColor(ShelfStyle.secondaryText) }
            Text(book.author).font(.subheadline).foregroundColor(ShelfStyle.secondaryText)
            if let duration = listeningDuration { Label(ShelfTime.describe(duration), systemImage: "headphones").font(.subheadline) }
            if let narrators = book.media.metadata.narrators, !narrators.isEmpty {
                Text(l10n("Narrated by {0}", narrators.joined(separator: ", "))).font(.footnote).foregroundColor(ShelfStyle.secondaryText)
            }
            if episode == nil, book.mediaType == "book" { RelatedBookLinks(item: book, catalog: catalog) }
        }.multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func toggleFinished() {
        guard !progressBusy else { return }
        NativeHaptic.impact("toggle-finished")
        let finished = selectedProgress?.isFinished != true
        let livePosition = player.itemID == book.id && player.episodeID == nil ? player.currentTime : 0
        if episode == nil, finished, (selectedProgress?.currentTime ?? 0) > 0 || (selectedProgress?.ebookProgress ?? 0) > 0 || livePosition > 0 {
            progressConfirmation = .finish
        } else { applyFinished(finished) }
    }
    private func applyFinished(_ finished: Bool) {
        guard !progressBusy else { return }
        request?.cancel()
        detailRevision = UUID()
        progressBusy = true
        clearLoadFailure()
        progressRequest = Task {
            defer { progressBusy = false }
            do {
                let user = try await player.setFinished(itemID: book.id, episodeID: episode?.id, finished: finished)
                guard !Task.isCancelled else { return }
                mediaProgress = user.mediaProgress
                catalog.applyProgress(user)
            } catch {
                if !Task.isCancelled { recordLoadFailure(ConnectionStore.recovery(for: error)) }
                await refreshWaitingWrites()
            }
        }
    }

    private func discardProgress() {
        guard !progressBusy else { return }
        request?.cancel()
        detailRevision = UUID()
        progressBusy = true
        error = nil
        progressRequest = Task {
            defer { progressBusy = false }
            do {
                let account = try await catalog.api.currentAccount()
                let user = try await migration.resetProgress(account: account, itemID: book.id, episodeID: episode?.id)
                guard !Task.isCancelled else { return }
                progressDiscarded = true
                mediaProgress = user.mediaProgress
                catalog.discardProgress(user, itemID: book.id, episodeID: episode?.id)
            } catch is ApplePlayback.UnresolvedProgressWrites {
                if !Task.isCancelled { self.error = .unresolvedWrites(l10n("Progress was kept. An earlier save of this title's progress got no answer, and the server may still apply it, which would bring the progress back. Try again to be guided through a server restart.")) }
            } catch { if !Task.isCancelled { self.error = .discard(ConnectionStore.recovery(for: error)) } }
        }
    }

    /// The restart is asked for before the alert shows, so a restart before it does not count.
    private func askForRestart(thenDiscard: Bool) {
        guard !progressBusy else { return }
        Task {
            do {
                try player.requestServerRestart(account: try await catalog.api.currentAccount())
                restartThenDiscard = thenDiscard
                progressConfirmation = .serverRestarted
            } catch { self.error = .discard(ConnectionStore.recovery(for: error)) }
        }
    }

    private func confirmRestart() {
        guard !progressBusy else { return }
        Task {
            do {
                try player.confirmServerRestarted(account: try await catalog.api.currentAccount())
                if restartThenDiscard { discardProgress(); return }
                // Sends what waited.
                await player.restoreListening()
                readingStore.sync(api: catalog.api)
                await refreshWaitingWrites()
                load()
            } catch { self.error = .discard(ConnectionStore.recovery(for: error)) }
        }
    }

    private func refreshWaitingWrites() async {
        guard let account = try? await catalog.api.currentAccount() else { return }
        writesWaiting = player.publications.unresolved(account: account, itemID: book.id, episodeID: episode?.id)
    }

    // After a discard the progress this view was opened with is stale.
    private var selectedProgress: MediaProgress? {
        mediaProgress.first { $0.libraryItemId == book.id && $0.episodeId == episode?.id } ?? (progressDiscarded ? nil : progress)
    }
    private var listeningDuration: Double? {
        if let episode { return episode.duration ?? episode.audioFile?.duration }
        return book.media.duration
    }
    private func progress(for episode: Episode) -> MediaProgress? {
        mediaProgress.first { $0.libraryItemId == book.id && $0.episodeId == episode.id }
    }
    private var visibleEpisodes: [Episode] {
        (book.media.episodes ?? []).filter { episode in
            let progress = progress(for: episode)
            switch episodeFilter {
            case "complete": return progress?.isFinished == true
            case "incomplete": return progress?.isFinished != true
            case "inProgress": return progress != nil && progress?.isFinished != true
            case "downloaded": return localDownloads.visible.contains { $0.media.libraryItemID == book.id && $0.media.episodeID == episode.id && $0.state == .ready }
            default: return true
            }
        }.sorted { left, right in
            func value(_ episode: Episode) -> String {
                switch episodeSort {
                case "title": return episode.title
                case "season": return episode.season ?? ""
                case "episode": return episode.episode ?? ""
                case "filename": return episode.audioFile?.metadata?.filename ?? ""
                default: return String(episode.publishedAt ?? 0)
                }
            }
            let comparison = value(left).localizedStandardCompare(value(right))
            if comparison == .orderedSame { return left.id < right.id }
            return comparison == (episodeDescending ? .orderedDescending : .orderedAscending)
        }
    }
    private var podcastEpisodes: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(l10n("Episodes")).font(.title2.bold())
                Spacer()
                Menu {
                    ForEach([("Published date", "publishedAt"), ("Title", "title"), ("Season", "season"), ("Episode number", "episode"), ("Filename", "filename")], id: \.1) { choice in
                        Button(l10n(choice.0)) { NativeHaptic.impact("sort"); episodeSort = choice.1 }
                    }
                    Button(l10n(episodeDescending ? "Ascending order" : "Descending order")) { NativeHaptic.impact("sort"); episodeDescending.toggle() }
                } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel(l10n("Sort episodes"))
                Menu {
                    Button(l10n("All episodes")) { NativeHaptic.impact("filter"); episodeFilter = "all" }
                    Button(l10n("Incomplete")) { NativeHaptic.impact("filter"); episodeFilter = "incomplete" }
                    Button(l10n("In progress")) { NativeHaptic.impact("filter"); episodeFilter = "inProgress" }
                    Button(l10n("Complete")) { NativeHaptic.impact("filter"); episodeFilter = "complete" }
                    Button(l10n("Downloaded")) { NativeHaptic.impact("filter"); episodeFilter = "downloaded" }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.accessibilityLabel(l10n("Filter episodes"))
            }
            if canManagePodcasts, book.media.metadata.feedUrl?.isEmpty == false {
                Button { showingFeed = true } label: { Label(l10n("Feed episodes"), systemImage: "dot.radiowaves.left.and.right") }
            }
            ForEach(downloads) { download in
                HStack {
                    Image(systemName: download.failed ? "exclamationmark.triangle" : download.isFinished ? "checkmark.circle" : "arrow.down.circle")
                    Text(download.episodeDisplayTitle ?? l10n("Podcast episode"))
                    Spacer()
                    Text(l10n(download.failed ? "Failed" : download.isFinished ? "Ready" : "Downloading on server")).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                }
            }
            if let error = serverQueue.error { Text(error).font(.caption).foregroundColor(.red) }
            if serverQueue.hasUnsavedResults { Button(l10n("Retry saving download results"), action: serverQueue.retrySavingResults) }
            ForEach(serverQueue.failures(itemID: item.id)) { failure in
                HStack { Image(systemName: "exclamationmark.triangle"); Text(failure.title); Spacer(); Text(l10n("Failed")).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
            }
            if !serverQueue.failures(itemID: item.id).isEmpty { Button(l10n("Retry failed episodes")) { showingFeed = true } }
            if !requestedDownloads.isEmpty {
                Text(l10n("Waiting for {0} episode(s) from your server", requestedDownloads.count)).font(.caption).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier("server-download-pending")
                Button(l10n("Refresh downloads"), action: watchDownloads)
            }
            if visibleEpisodes.isEmpty { Text(l10n("No episodes found")).foregroundColor(ShelfStyle.secondaryText) }
            ForEach(visibleEpisodes) { episode in
                NavigationLink(destination: BookDetails(item: book, catalog: catalog, progress: progress(for: episode), episode: episode)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.title).font(.headline).foregroundColor(.primary)
                        HStack {
                            if let published = episode.publishedAt { Text(Date(timeIntervalSince1970: published / 1000), style: .date) }
                            if let duration = episode.duration { Text(ShelfTime.describe(duration)) }
                        }.font(.caption).foregroundColor(ShelfStyle.secondaryText)
                        if let progress = progress(for: episode) {
                            ProgressView(value: progress.fraction).accentColor(ShelfStyle.accent)
                            Text(progress.isFinished == true ? l10n("Finished") : l10n("{0} listened", ShelfTime.describe(progress.currentTime ?? 0))).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(appearance.card).cornerRadius(16)
                }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("episode-\(episode.id)")
            }
        }
    }

    private func clearLoadFailure() {
        if case .load? = error { error = nil }
    }

    private func recordLoadFailure(_ message: String) {
        switch error { case .discard?, .unresolvedWrites?: return; default: break }
        error = .load(message)
    }

    private func watchDownloads() {
        downloadRequest?.cancel()
        downloadRequest = Task {
            do {
                while !Task.isCancelled {
                    let owner = try await catalog.api.currentAccount()
                    async let queue = catalog.api.podcastDownloads(itemID: book.id)
                    async let detail = catalog.api.item(id: book.id)
                    let (jobs, value) = try await (queue, detail)
                    guard !Task.isCancelled, try await catalog.api.currentAccount() == owner else { return }
                    downloads = jobs.filter { !$0.failed }
                    for job in jobs where job.failed { try serverQueue.receiveFailure(itemID: item.id, job: job) }
                    expanded = value
                    try serverQueue.reconcile(itemID: item.id, episodes: value.media.episodes ?? [])
                    if requestedDownloads.isEmpty, jobs.allSatisfy({ $0.isFinished || $0.failed }) { return }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            } catch { if !Task.isCancelled { recordLoadFailure(ConnectionStore.recovery(for: error)) } }
        }
    }

    private func receive(_ event: NativeRealtime.Event) {
        switch event.change {
        case .authenticated: load(monitorDownloads: true, for: event)
        case .user: load(for: event)
        case .progress(let itemID, _, _) where itemID == book.id: load(for: event)
        case .itemsUpdated(let items) where items.contains(where: { $0.id == book.id }): load(for: event)
        default: break
        }
    }

    /// `event` is the realtime change that asked for this load; nothing is fetched or shown unless the catalog owns it.
    private func load(monitorDownloads: Bool = false, for event: NativeRealtime.Event? = nil) {
        guard !progressBusy, event.map(catalog.owns) != false else { return }
        request?.cancel()
        let revision = UUID()
        detailRevision = revision
        request = Task {
            do {
                let owner = try await catalog.api.currentAccount()
                async let detail = catalog.api.item(id: item.id)
                async let account = catalog.api.me()
                let (value, user) = try await (detail, account)
                guard !Task.isCancelled, detailRevision == revision, try await catalog.api.currentAccount() == owner, event.map(catalog.owns) != false else { return }
                expanded = value
                mediaProgress = user.mediaProgress
                await refreshWaitingWrites()
                canManagePodcasts = user.canManagePodcasts
                if book.mediaType == "podcast", episode == nil {
                    try serverQueue.adoptLegacy(itemID: item.id)
                    try serverQueue.reconcile(itemID: item.id, episodes: book.media.episodes ?? [])
                }
                clearLoadFailure()
                if monitorDownloads, book.mediaType == "podcast", episode == nil, canManagePodcasts { watchDownloads() }
            } catch {
                guard !Task.isCancelled, detailRevision == revision, event.map(catalog.owns) != false else { return }
                recordLoadFailure(ConnectionStore.recovery(for: error))
            }
        }
    }

    private static func plainDescription(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
