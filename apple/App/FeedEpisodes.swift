import SwiftUI

struct FeedEpisodes: View {
    let api: APIClient
    let item: LibraryItem
    @Binding var presented: Bool
    enum QueueChange { case requested([PodcastFeedEpisode]), accepted, rejected([PodcastFeedEpisode]) }
    let onQueueChange: (QueueChange) throws -> Void
    @State private var episodes: [PodcastFeedEpisode] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var adding = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @Environment(\.nativeStrings) private var l10n
    private var existing: Set<String> { Set((item.media.episodes ?? []).compactMap { $0.enclosure?.url }) }
    var body: some View {
        NavigationView {
            ShelfList {
                if loading { ProgressView(l10n("Opening podcast feed…")) }
                if let error {
                    Text(error).foregroundColor(.red)
                    Button(l10n("Retry feed"), action: load).disabled(adding)
                }
                if !loading, episodes.isEmpty { Text(l10n("No feed episodes found")).foregroundColor(.secondary) }
                ForEach(episodes) { episode in
                    Button {
                        if selected.contains(episode.id) { selected.remove(episode.id) }
                        else { selected.insert(episode.id) }
                    } label: {
                        HStack {
                            Image(systemName: existing.contains(episode.enclosureURL ?? "") ? "checkmark.circle.fill" : selected.contains(episode.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(episode.title)
                                if existing.contains(episode.enclosureURL ?? "") { Text(l10n("Already on server")).font(.caption).foregroundColor(.secondary) }
                                else if episode.enclosureURL == nil { Text(l10n("No audio enclosure")).font(.caption).foregroundColor(.secondary) }
                            }
                        }
                    }.disabled(adding || episode.enclosureURL == nil || existing.contains(episode.enclosureURL ?? ""))
                        .accessibilityLabel(episode.title).accessibilityValue(l10n(selected.contains(episode.id) ? "Selected" : "Not selected"))
                }
                Button(l10n("Add selected episodes to server"), action: queue).disabled(selected.isEmpty || adding || loading)
                if adding { ProgressView(l10n("Queueing on your server…")) }
            }.navigationTitle(l10n("Feed episodes")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(l10n("Done")) { request?.cancel(); presented = false } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear(perform: load).onDisappear { request?.cancel() }
    }
    private func load() {
        guard !adding, let url = item.media.metadata.feedUrl else { loading = false; return }
        request?.cancel()
        loading = true; error = nil
        request = Task {
            do {
                let response = try await api.podcastFeed(url: url)
                guard !Task.isCancelled else { return }
                episodes = response.episodes ?? []
                selected.formIntersection(Set(episodes.map(\.id)))
                loading = false
            } catch { if !Task.isCancelled { loading = false; self.error = ConnectionStore.recovery(for: error) } }
        }
    }
    private func queue() {
        guard !adding else { return }
        let choices = episodes.filter { selected.contains($0.id) }
        guard !choices.isEmpty else { return }
        NativeHaptic.impact("episodes-queue")
        adding = true; error = nil
        request = Task {
            defer { adding = false }
            do {
                try onQueueChange(.requested(choices))
                try await api.downloadFeedEpisodes(itemID: item.id, episodes: choices)
                guard !Task.isCancelled else { return }
                try onQueueChange(.accepted)
                presented = false
            } catch {
                if !Task.isCancelled {
                    if case APIError.http(let code) = error, [400, 401, 403, 404, 413].contains(code) { try? onQueueChange(.rejected(choices)) }
                    self.error = ConnectionStore.recovery(for: error)
                }
            }
        }
    }
}
