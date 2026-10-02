import SwiftUI

/// Loads expanded item details once per screen and starts playback in the shared session.
@MainActor final class ItemDetail: ObservableObject {
    @Published private(set) var item: LibraryItem?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var busy = false

    func load(_ id: String, catalog: CatalogStore) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let detail = catalog.api.item(id: id)
            await catalog.refreshProgress()
            item = try await detail
        } catch {
            catalog.noteAuthentication(error)
            TVDiagnostics.shared.record(error, detail: "Details")
            self.error = CatalogStore.recovery(for: error)
        }
    }

    func play(_ item: LibraryItem, episode: Episode? = nil, restart: Bool, player: TVPlayer, navigator: TVNavigator) async {
        error = nil
        await player.start(item: item, episode: episode)
        // A start that could not replace the playing title leaves it in place; the failure shows here instead (#112).
        guard player.session != nil, player.itemID == item.id, player.episodeID == episode?.id else { return }
        if restart {
            do { try await player.seek(to: 0, autoplay: true) }
            catch {
                TVDiagnostics.shared.record(error, detail: "Play again")
                self.error = NativeStrings.current("Could not start from the beginning: {0}", CatalogStore.recovery(for: error))
                return
            }
        }
        navigator.tab = .nowPlaying
    }

    func setFinished(_ finished: Bool, itemID: String, episodeID: String?, player: TVPlayer, catalog: CatalogStore) async {
        busy = true; error = nil
        defer { busy = false }
        do { catalog.remember(try await player.setFinished(itemID: itemID, episodeID: episodeID, finished: finished)) }
        catch is CancellationError {}
        catch {
            catalog.noteAuthentication(error)
            TVDiagnostics.shared.record(error, detail: finished ? "Mark as finished" : "Mark as not finished")
            self.error = CatalogStore.recovery(for: error)
        }
    }
}

struct PlaybackActions: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @EnvironmentObject private var navigator: TVNavigator
    @ObservedObject var detail: ItemDetail
    let item: LibraryItem
    var episode: Episode?
    var playIdentifier = "play-item"

    var body: some View {
        let state = catalog.progress(itemID: item.id, episodeID: episode?.id)
        let current = player.session != nil && player.itemID == item.id && player.episodeID == episode?.id
        let finished = state?.isFinished == true
        let action = current ? l10n("Now Playing") : finished ? l10n("Play again") : (state?.currentTime ?? 0) > 0 ? l10n("Resume") : l10n("Play")
        let completion = finished ? l10n("Mark as not finished") : l10n("Mark as finished")
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 30) {
                Button {
                    if current { navigator.tab = .nowPlaying; return }
                    Task { await detail.play(item, episode: episode, restart: finished, player: player, navigator: navigator) }
                } label: {
                    Label(player.preparing && !current ? l10n("Preparing…") : action, systemImage: current ? "waveform" : "play.fill")
                }
                .accessibilityIdentifier(playIdentifier)
                .accessibilityLabel(action)
                .disabled(player.preparing || player.seeking || detail.busy)
                Button {
                    Task { await detail.setFinished(!finished, itemID: item.id, episodeID: episode?.id, player: player, catalog: catalog) }
                } label: {
                    Label(completion, systemImage: finished ? "arrow.uturn.backward" : "checkmark")
                }
                .accessibilityIdentifier("mark-finished")
                .accessibilityLabel(completion)
                .disabled(detail.busy || player.preparing)
            }
            if let failure = detail.error ?? (current ? nil : player.error) {
                Text(failure).foregroundStyle(.orange).accessibilityIdentifier("detail-error")
            }
        }
    }
}

struct ItemDetailView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    let item: LibraryItem
    @StateObject private var detail = ItemDetail()
    @State private var newestFirst = true

    var body: some View {
        let loaded = detail.item ?? item
        let metadata = loaded.media.metadata
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                HStack(alignment: .top, spacing: 70) {
                    CoverView(itemID: item.id, podcast: item.isPodcast)
                        .frame(width: 440, height: 440).clipShape(RoundedRectangle(cornerRadius: 22))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 22) {
                        Text(loaded.title).font(.system(size: 52, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail-title")
                        if !loaded.author.isEmpty { Text(loaded.author).font(.title3).foregroundStyle(.secondary) }
                        if let narrators = metadata.narrators, !narrators.isEmpty {
                            Text(l10n("Narrated by {0}", narrators.joined(separator: ", "))).foregroundStyle(.secondary)
                                .accessibilityIdentifier("detail-narrators")
                        }
                        Text(facts(loaded)).foregroundStyle(.secondary)
                        if !loaded.isPodcast {
                            if let state = Format.progress(catalog.progress(itemID: item.id), duration: loaded.media.duration, strings: l10n) {
                                Text(state).font(.headline).accessibilityIdentifier("detail-progress")
                            }
                            if detail.item != nil { PlaybackActions(detail: detail, item: loaded).focusSection() }
                        }
                        if detail.item != nil { RelatedLinks(item: loaded) }
                        if detail.loading && detail.item == nil { ProgressView(l10n("Loading details…")) }
                        if let error = detail.error, detail.item == nil {
                            Text(error).foregroundStyle(.orange).accessibilityIdentifier("detail-error")
                            Button(l10n("Try again")) { Task { await detail.load(item.id, catalog: catalog) } }
                        }
                        if let description = metadata.description.map(Format.plainText), !description.isEmpty {
                            Text(description).font(.body).foregroundStyle(.secondary).lineLimit(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if loaded.isPodcast, detail.item != nil { episodes(loaded) }
            }
            .padding(80)
        }
        .task { if detail.item == nil { await detail.load(item.id, catalog: catalog) } }
    }

    private func facts(_ item: LibraryItem) -> String {
        var facts: [String] = []
        if let duration = item.media.duration, duration.isFinite, duration > 0, duration < 1e7 { facts.append(Format.duration(duration, locale: l10n.language.locale)) }
        if let chapters = item.media.chapters, chapters.count > 1 { facts.append(l10n("{0} chapters", chapters.count)) }
        if let episodes = item.media.episodes { facts.append(episodes.count == 1 ? l10n("1 episode") : l10n("{0} episodes", episodes.count)) }
        if let genres = item.media.metadata.genres, !genres.isEmpty { facts.append(genres.prefix(3).joined(separator: ", ")) }
        return facts.joined(separator: " · ")
    }

    @ViewBuilder private func episodes(_ podcast: LibraryItem) -> some View {
        let sorted = (podcast.media.episodes ?? []).sorted {
            let (left, right) = ($0.publishedAt ?? 0, $1.publishedAt ?? 0)
            return newestFirst ? left > right : left < right
        }
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(l10n("Episodes")).font(.title2.bold())
                Spacer()
                Button(newestFirst ? l10n("Newest first") : l10n("Oldest first")) { newestFirst.toggle() }
                    .accessibilityIdentifier("episode-sort")
            }
            .focusSection()
            if sorted.isEmpty { Text(l10n("No episodes have been downloaded to the server yet.")).foregroundStyle(.secondary) }
            ForEach(sorted) { episode in
                NavigationLink(value: Route.episode(podcast, episodeID: episode.id)) { EpisodeRow(item: podcast, episode: episode) }
                    .accessibilityIdentifier("episode-\(episode.id)")
            }
        }
    }
}

struct EpisodeRow: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    let item: LibraryItem
    let episode: Episode

    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text(episode.title).font(.headline).lineLimit(2)
                Text(Format.facts(episode, locale: l10n.language.locale)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let state = Format.progress(catalog.progress(itemID: item.id, episodeID: episode.id), duration: episode.playableDuration, strings: l10n) {
                Text(state).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("episode-state-\(episode.id)")
            }
        }
        .padding(.vertical, 8)
    }
}

struct EpisodeDetailView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var catalog: CatalogStore
    let item: LibraryItem
    let episodeID: String
    @StateObject private var detail = ItemDetail()

    var body: some View {
        let podcast = detail.item ?? item
        let episode = podcast.media.episodes?.first { $0.id == episodeID } ?? (item.recentEpisode?.id == episodeID ? item.recentEpisode : nil)
        ScrollView {
            HStack(alignment: .top, spacing: 70) {
                CoverView(itemID: item.id, podcast: true).frame(width: 400, height: 400).clipShape(RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 22) {
                    Text(podcast.title).font(.title3).foregroundStyle(.secondary)
                    if let episode {
                        Text(episode.title).font(.system(size: 48, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("episode-title")
                        Text(Format.facts(episode, locale: l10n.language.locale)).foregroundStyle(.secondary)
                        if let state = Format.progress(catalog.progress(itemID: item.id, episodeID: episodeID), duration: episode.playableDuration, strings: l10n) {
                            Text(state).font(.headline).accessibilityIdentifier("episode-progress")
                        }
                        if detail.item != nil { PlaybackActions(detail: detail, item: podcast, episode: episode, playIdentifier: "play-episode").focusSection() }
                        if let description = episode.description.map(Format.plainText), !description.isEmpty {
                            Text(description).foregroundStyle(.secondary).lineLimit(10)
                        }
                    }
                    if detail.loading && detail.item == nil { ProgressView(l10n("Loading episode…")) }
                    if let error = detail.error, detail.item == nil {
                        Text(error).foregroundStyle(.orange).accessibilityIdentifier("detail-error")
                        Button(l10n("Try again")) { Task { await detail.load(item.id, catalog: catalog) } }
                    } else if detail.item != nil && episode == nil {
                        Text(l10n("This episode is no longer available on the server.")).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(80)
        }
        .task { if detail.item == nil { await detail.load(item.id, catalog: catalog) } }
    }
}
