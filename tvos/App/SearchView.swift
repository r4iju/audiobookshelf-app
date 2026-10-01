import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @State private var query = ""
    @State private var results: [LibraryItem] = []
    @State private var searching = false
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 260), spacing: 48, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if let error {
                        StatusMessage(text: error, identifier: "search-error", retryIdentifier: "retry-search") { Task { await search() } }
                    } else if searching && results.isEmpty {
                        ProgressView("Searching…").frame(maxWidth: .infinity)
                    } else if !query.isEmpty && results.isEmpty {
                        Text("No titles or episodes match “\(query)”.").font(.title3).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
                        ForEach(results) { item in
                            NavigationLink(value: Route.to(item)) { ItemTile(item: item) }
                                .buttonStyle(.card)
                                .accessibilityIdentifier("search.\(item.id)")
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
        guard !text.isEmpty else { results = []; return }
        searching = true
        defer { searching = false }
        do {
            let found = try await catalog.search(text)
            guard text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = found
        } catch is CancellationError {
        } catch {
            catalog.noteAuthentication(error)
            self.error = CatalogStore.recovery(for: error)
        }
    }
}
