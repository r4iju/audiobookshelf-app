import SwiftUI

struct AddPodcast: View {
    @ObservedObject var catalog: CatalogStore
    @Binding var presented: Bool
    @State private var feedURL = ""
    @State private var feed: PodcastFeed?
    @State private var title = ""
    @State private var author = ""
    @State private var description = ""
    @State private var folderID = ""
    @State private var autoDownload = false
    @State private var busy = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var query = ""
    @State private var results: [PodcastDiscovery] = []
    @State private var searchCompleted = false
    @State private var discovery: PodcastDiscovery?
    private var folders: [LibraryFolder] { catalog.library.folders ?? [] }
    private var permitted: Bool {
        if case .content(let content) = catalog.state { return content.user.canManagePodcasts }
        return false
    }
    var body: some View {
        NavigationView {
            ShelfForm {
                if feed == nil {
                    Section(header: Text("Discover a podcast")) {
                        TextField("Podcast name", text: $query).accessibilityIdentifier("podcast-discovery-query").disabled(busy)
                        Button("Search podcasts", action: search).disabled(busy || !permitted || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if searchCompleted, results.isEmpty { Text("No podcasts found").foregroundColor(.secondary) }
                        ForEach(results) { result in
                            Button {
                                guard let url = result.feedUrl else { return }
                                feedURL = url
                                discovery = result
                                preview()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.title)
                                    if let author = result.artistName { Text(author).font(.caption).foregroundColor(.secondary) }
                                }
                            }.disabled(busy || result.feedUrl == nil).accessibilityIdentifier("podcast-discovery-\(result.id)")
                        }
                    }
                }
                Section(header: Text("Podcast feed")) {
                    TextField("RSS feed URL", text: $feedURL).keyboardType(.URL).autocapitalization(.none).disableAutocorrection(true)
                        .accessibilityIdentifier("podcast-feed-url").disabled(busy)
                    Button("Preview feed", action: preview).disabled(busy || !permitted || feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if feed != nil {
                    Section(header: Text("Add to your library")) {
                        TextField("Title", text: $title).accessibilityIdentifier("podcast-title")
                        TextField("Author", text: $author)
                        TextEditor(text: $description).frame(minHeight: 100).accessibilityLabel("Description")
                        Picker("Server folder", selection: $folderID) {
                            ForEach(folders) { folder in Text(folder.fullPath).tag(folder.id) }
                        }
                        Toggle("Automatically download new episodes", isOn: $autoDownload)
                        Button("Create podcast", action: create).disabled(!permitted || busy || folders.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.disabled(busy)
                    if folders.isEmpty { Text("This library has no server folder. Add one in server settings before creating a podcast.").foregroundColor(.secondary) }
                }
                if busy { ProgressView("Contacting your server…") }
                if let error { Text(error).foregroundColor(.red).accessibilityIdentifier("podcast-action-error") }
            }.navigationTitle("Add podcast").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { request?.cancel(); presented = false } } }
        }.navigationViewStyle(StackNavigationViewStyle())
            .onChange(of: feedURL) { _ in if !busy { feed = nil; discovery = nil } }
            .onDisappear { request?.cancel() }
    }
    private func search() {
        guard permitted, !busy else { return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        busy = true; error = nil; searchCompleted = false; feed = nil; discovery = nil
        request = Task {
            defer { busy = false }
            do {
                let values = try await catalog.api.discoverPodcasts(term: term)
                guard !Task.isCancelled else { return }
                results = values
                searchCompleted = true
            } catch { if !Task.isCancelled { self.error = ConnectionStore.recovery(for: error) } }
        }
    }
    private func preview() {
        guard permitted, !busy else { return }
        let url = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil else {
            error = "Enter a complete HTTP or HTTPS RSS feed URL."
            return
        }
        busy = true; error = nil
        request = Task {
            defer { busy = false }
            do {
                let value = try await catalog.api.podcastFeed(url: url)
                guard !Task.isCancelled else { return }
                feed = value
                title = discovery?.title ?? value.metadata.title ?? ""
                author = discovery?.artistName ?? value.metadata.author ?? ""
                description = discovery?.descriptionPlain ?? value.metadata.descriptionPlain ?? ""
                results = []
                folderID = folders.first?.id ?? ""
            } catch { if !Task.isCancelled { self.error = ConnectionStore.recovery(for: error) } }
        }
    }
    private func create() {
        guard permitted, !busy, let feed, let folder = folders.first(where: { $0.id == folderID }) else { return }
        busy = true; error = nil
        request = Task {
            defer { busy = false }
            do {
                _ = try await catalog.api.createPodcast(libraryID: catalog.library.id, folder: folder,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines), author: author,
                    description: description, feed: feed, feedURL: feedURL.trimmingCharacters(in: .whitespacesAndNewlines), autoDownload: autoDownload, discovery: discovery)
                guard !Task.isCancelled else { return }
                await catalog.reload()
                guard !Task.isCancelled else { return }
                presented = false
            } catch { if !Task.isCancelled { self.error = ConnectionStore.recovery(for: error) } }
        }
    }
}
