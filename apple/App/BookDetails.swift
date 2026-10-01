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
    @Environment(\.nativeStrings) private var l10n
    let item: LibraryItem
    let catalog: CatalogStore
    let progress: MediaProgress?
    let episode: Episode?
    @State private var expanded: LibraryItem?
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var playAttempted = false
    @State private var mediaProgress: [MediaProgress] = []
    @AppStorage("previewEpisodeSort") private var episodeSort = "publishedAt"
    @AppStorage("previewEpisodeDescending") private var episodeDescending = true
    @State private var episodeFilter = "all"
    @State private var confirmCompletion = false
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
                    }.padding(18).foregroundColor(.white).background(ShelfStyle.accent).cornerRadius(16)
                }.disabled(player.preparing || progressBusy).accessibilityIdentifier("play-book")
                }
                if episode != nil || book.mediaType == "book" {
                    Button(l10n(selectedProgress?.isFinished == true ? "Mark unfinished" : "Mark finished"), action: toggleFinished).disabled(progressBusy)
                    if progressBusy { ProgressView(l10n("Saving your progress…")) }
                }
                if let error = player.error, player.itemID == book.id || playAttempted { Text(error).font(.callout).foregroundColor(.red) }
                if let ebook = book.media.ebookFile, ["pdf", "epub"].contains(ebook.format), episode == nil {
                    Button(l10n("Read {0}", ebook.format.uppercased())) {
                        Task {
                            do { reader = ReadingSource(account: try await catalog.api.currentAccount(), itemID: book.id, title: book.title, ebook: ebook, file: nil) }
                            catch { self.error = error.localizedDescription }
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
                                        catch { self.error = error.localizedDescription }
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
                if let progress = selectedProgress, (progress.currentTime ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress.fraction).accentColor(ShelfStyle.accent)
                        Text(l10n("{0} listened · {1}% complete", ShelfTime.describe(progress.currentTime ?? 0), Int(progress.fraction * 100))).font(.caption).foregroundColor(.secondary)
                    }
                }
                if let description = episode?.description ?? book.media.metadata.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n(episode != nil ? "About this episode" : book.mediaType == "podcast" ? "About this podcast" : "About this book")).font(.title3.bold())
                        Text(Self.plainDescription(description)).font(.body).lineSpacing(5).foregroundColor(.secondary)
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
                                Text(ShelfTime.describe(chapter.end - chapter.start)).font(.caption).foregroundColor(.secondary)
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                if let error { RecoveryCard(message: error) { load(monitorDownloads: true) } }
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
            .alert(isPresented: $confirmCompletion) {
                Alert(title: Text(l10n("Mark book finished?")), message: Text(l10n("Your saved progress will change when this book is marked finished.")), primaryButton: .default(Text(l10n("Mark finished"))) { applyFinished(true) }, secondaryButton: .cancel(Text(l10n("Cancel"))))
            }
            .onChange(of: serverQueue.revision) { _ in if book.mediaType == "podcast", episode == nil, canManagePodcasts { watchDownloads() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in load(monitorDownloads: true) }
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
            if episode != nil { Text(book.title).font(.subheadline).foregroundColor(.secondary) }
            Text(book.author).font(.subheadline).foregroundColor(.secondary)
            if let duration = listeningDuration { Label(ShelfTime.describe(duration), systemImage: "headphones").font(.subheadline) }
            if let narrators = book.media.metadata.narrators, !narrators.isEmpty {
                Text(l10n("Narrated by {0}", narrators.joined(separator: ", "))).font(.footnote).foregroundColor(.secondary)
            }
        }.multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func toggleFinished() {
        guard !progressBusy else { return }
        NativeHaptic.impact("toggle-finished")
        let finished = selectedProgress?.isFinished != true
        let livePosition = player.itemID == book.id && player.episodeID == nil ? player.currentTime : 0
        if episode == nil, finished, (selectedProgress?.currentTime ?? 0) > 0 || (selectedProgress?.ebookProgress ?? 0) > 0 || livePosition > 0 {
            confirmCompletion = true
        } else { applyFinished(finished) }
    }
    private func applyFinished(_ finished: Bool) {
        guard !progressBusy else { return }
        request?.cancel()
        detailRevision = UUID()
        progressBusy = true
        error = nil
        progressRequest = Task {
            defer { progressBusy = false }
            do {
                let user = try await player.setFinished(itemID: book.id, episodeID: episode?.id, finished: finished)
                guard !Task.isCancelled else { return }
                mediaProgress = user.mediaProgress
                catalog.applyProgress(user)
            } catch { if !Task.isCancelled { self.error = ConnectionStore.recovery(for: error) } }
        }
    }

    private var selectedProgress: MediaProgress? {
        mediaProgress.first { $0.libraryItemId == book.id && $0.episodeId == episode?.id } ?? progress
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
                    Text(l10n(download.failed ? "Failed" : download.isFinished ? "Ready" : "Downloading on server")).font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = serverQueue.error { Text(error).font(.caption).foregroundColor(.red) }
            if serverQueue.hasUnsavedResults { Button(l10n("Retry saving download results"), action: serverQueue.retrySavingResults) }
            ForEach(serverQueue.failures(itemID: item.id)) { failure in
                HStack { Image(systemName: "exclamationmark.triangle"); Text(failure.title); Spacer(); Text(l10n("Failed")).font(.caption).foregroundColor(.secondary) }
            }
            if !serverQueue.failures(itemID: item.id).isEmpty { Button(l10n("Retry failed episodes")) { showingFeed = true } }
            if !requestedDownloads.isEmpty {
                Text(l10n("Waiting for {0} episode(s) from your server", requestedDownloads.count)).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("server-download-pending")
                Button(l10n("Refresh downloads"), action: watchDownloads)
            }
            if visibleEpisodes.isEmpty { Text(l10n("No episodes found")).foregroundColor(.secondary) }
            ForEach(visibleEpisodes) { episode in
                NavigationLink(destination: BookDetails(item: book, catalog: catalog, progress: progress(for: episode), episode: episode)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.title).font(.headline).foregroundColor(.primary)
                        HStack {
                            if let published = episode.publishedAt { Text(Date(timeIntervalSince1970: published / 1000), style: .date) }
                            if let duration = episode.duration { Text(ShelfTime.describe(duration)) }
                        }.font(.caption).foregroundColor(.secondary)
                        if let progress = progress(for: episode) {
                            ProgressView(value: progress.fraction).accentColor(ShelfStyle.accent)
                            Text(progress.isFinished == true ? l10n("Finished") : l10n("{0} listened", ShelfTime.describe(progress.currentTime ?? 0))).font(.caption).foregroundColor(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(appearance.card).cornerRadius(16)
                }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("episode-\(episode.id)")
            }
        }
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
            } catch { if !Task.isCancelled { self.error = ConnectionStore.recovery(for: error) } }
        }
    }

    private func load(monitorDownloads: Bool = false) {
        guard !progressBusy else { return }
        request?.cancel()
        let revision = UUID()
        detailRevision = revision
        request = Task {
            do {
                let owner = try await catalog.api.currentAccount()
                async let detail = catalog.api.item(id: item.id)
                async let account = catalog.api.me()
                let (value, user) = try await (detail, account)
                guard !Task.isCancelled, detailRevision == revision, try await catalog.api.currentAccount() == owner else { return }
                expanded = value
                mediaProgress = user.mediaProgress
                canManagePodcasts = user.canManagePodcasts
                if book.mediaType == "podcast", episode == nil {
                    try serverQueue.adoptLegacy(itemID: item.id)
                    try serverQueue.reconcile(itemID: item.id, episodes: book.media.episodes ?? [])
                }
                error = nil
                if monitorDownloads, book.mediaType == "podcast", episode == nil, canManagePodcasts { watchDownloads() }
            } catch {
                guard !Task.isCancelled, detailRevision == revision else { return }
                self.error = ConnectionStore.recovery(for: error)
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
