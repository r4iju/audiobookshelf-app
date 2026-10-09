import SwiftUI

struct SearchView: View {
    @Environment(\.nativeStrings) private var l10n
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
                        ProgressView(l10n("Searching…")).frame(maxWidth: .infinity)
                    } else if !query.isEmpty && found.titles.isEmpty && found.related.isEmpty {
                        Text(l10n("No titles, episodes, authors or series match “{0}”.", query)).font(.title3).foregroundStyle(.secondary)
                    }
                    if query.isEmpty {
                        TVReadableText(text: l10n("Search all your libraries."), identifier: "search-scope")
                    }
                    related(l10n("Authors"), routes: found.related.filter { if case .author = $0 { return true }; return false })
                    related(l10n("Series"), routes: found.related.filter { if case .series = $0 { return true }; return false })
                    titles(l10n("Titles"), results: found.titles.filter { $0.episodeID == nil })
                    titles(l10n("Episodes"), results: found.titles.filter { $0.episodeID != nil })
                }
                .padding(.horizontal, 80)
            }
            .searchable(text: $query, prompt: l10n("Titles, authors, narrators or episodes"))
            .catalogRoutes()
        }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    @ViewBuilder private func related(_ title: String, routes: [Route]) -> some View {
        if !routes.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2.weight(.semibold))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 30) {
                        ForEach(routes, id: \.self) { route in
                            NavigationLink(value: route) { RelatedLabel(route: route) }
                                .accessibilityIdentifier("search." + (route.relatedIdentifier ?? ""))
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }

    @ViewBuilder private func titles(_ title: String, results: [SearchResult]) -> some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.title2.weight(.semibold))
                LazyVGrid(columns: TileGrid.columns, alignment: .leading, spacing: 56) {
                    ForEach(results) { result in
                        NavigationLink(value: result.route) { ItemTile(item: result.item, episodeID: result.episodeID) }
                            .buttonStyle(.card)
                            .buttonBorderShape(.roundedRectangle(radius: 24))
                            .accessibilityIdentifier("search." + result.item.id + (result.episodeID.map { "." + $0 } ?? ""))
                    }
                }
            }
            .focusSection()
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
            TVDiagnostics.shared.record(error, detail: "Search")
            self.error = CatalogStore.recovery(for: error, in: l10n)
        }
    }
}
