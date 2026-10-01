import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @State private var query = ""
    @State private var found = SearchFound()
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if let error {
                        StatusMessage(text: error, identifier: "search-error", retryIdentifier: "retry-search") { Task { await search() } }
                    } else if searching && found.titles.isEmpty && found.related.isEmpty {
                        ProgressView("Searching…").frame(maxWidth: .infinity)
                    } else if !query.isEmpty && found.titles.isEmpty && found.related.isEmpty {
                        Text("No titles, episodes, authors or series match “\(query)”.").font(.title3).foregroundStyle(.secondary)
                    }
                    if !found.related.isEmpty {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 30) {
                                ForEach(found.related, id: \.self) { route in
                                    NavigationLink(value: route) { RelatedLabel(route: route) }
                                        .accessibilityIdentifier("search." + (route.relatedIdentifier ?? ""))
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .scrollClipDisabled()
                        .focusSection()
                    }
                    LazyVGrid(columns: TileGrid.columns, alignment: .leading, spacing: 56) {
                        ForEach(found.titles) { result in
                            NavigationLink(value: result.route) { ItemTile(item: result.item, episodeID: result.episodeID) }
                                .buttonStyle(.card)
                                .accessibilityIdentifier("search." + result.item.id + (result.episodeID.map { "." + $0 } ?? ""))
                        }
                    }
                }
                .padding(.horizontal, 80)
            }
            .searchable(text: $query, prompt: "Titles, authors, narrators or episodes")
            .catalogRoutes()
        }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        guard !text.isEmpty else { found = SearchFound(); return }
        searching = true
        defer { searching = false }
        do {
            let results = try await catalog.search(text)
            guard text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            found = results
        } catch is CancellationError {
        } catch {
            catalog.noteAuthentication(error)
            self.error = CatalogStore.recovery(for: error)
        }
    }
}
