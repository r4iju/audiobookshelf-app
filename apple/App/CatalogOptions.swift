import SwiftUI

enum CatalogSort: String, CaseIterable {
    case title = "media.metadata.title", author = "media.metadata.authorName", authorLast = "media.metadata.authorNameLF"
    case year = "media.metadata.publishedYear", added = "addedAt", size, duration = "media.duration"
    case fileCreated = "birthtimeMs", fileModified = "mtimeMs", progress, started = "progress.createdAt", finished = "progress.finishedAt", random
    case podcastAuthor = "media.metadata.author", episodes = "media.numTracks"
    static func available(for mediaType: String) -> [CatalogSort] {
        if mediaType == "podcast" { return [.title, .podcastAuthor, .added, .size, .episodes, .fileCreated, .fileModified, .random] }
        return allCases.filter { $0 != .podcastAuthor && $0 != .episodes }
    }
    var name: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author, first name"
        case .authorLast: return "Author, last name"
        case .year: return "Published year"
        case .added: return "Date added"
        case .size: return "File size"
        case .duration: return "Duration"
        case .fileCreated: return "File created"
        case .fileModified: return "File modified"
        case .progress: return "Listening progress"
        case .started: return "Date started"
        case .finished: return "Date finished"
        case .random: return "Random"
        case .podcastAuthor: return "Author"
        case .episodes: return "Number of episodes"
        }
    }
}

struct CatalogFilterOptions: View {
    @ObservedObject var catalog: CatalogStore
    @Binding var presented: Bool
    @State private var data: LibraryFilters?
    @State private var error: String?
    var body: some View {
        NavigationView {
            ShelfList {
                if let error { Text(error).foregroundColor(.red); Button("Retry filters") { load() } }
                else if let data {
                    Button("All titles") { select(nil) }
                    group("Genres", key: "genres", values: data.genres ?? [])
                    group("Tags", key: "tags", values: data.tags ?? [])
                    namedGroup("Authors", key: "authors", values: data.authors ?? [])
                    namedGroup("Series", key: "series", values: data.series ?? [])
                    group("Narrators", key: "narrators", values: data.narrators ?? [])
                    group("Languages", key: "languages", values: data.languages ?? [])
                    if catalog.library.mediaType == "book" {
                        NavigationLink("Progress", destination: ShelfList {
                            option("Finished", group: "progress", value: "finished")
                            option("In progress", group: "progress", value: "in-progress")
                            option("Not started", group: "progress", value: "not-started")
                            option("Not finished", group: "progress", value: "not-finished")
                        }.navigationTitle("Progress"))
                        NavigationLink("Ebooks", destination: ShelfList {
                            option("Has ebook", group: "ebooks", value: "ebook")
                            option("Has supplementary ebook", group: "ebooks", value: "supplementary")
                        }.navigationTitle("Ebooks"))
                        Button("No series") { select("series." + Data("no-series".utf8).base64EncodedString()) }
                        Button("Items with issues") { select("issues") }
                    }
                    Button("Open RSS feeds") { select("feed-open") }
                    if canAccessExplicitContent { Button("Explicit content") { select("explicit") } }
                } else { ProgressView("Opening filters…") }
            }.navigationTitle("Filters").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { presented = false } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear { load() }
    }
    private func load() {
        error = nil
        Task { do { data = try await catalog.api.filters(libraryID: catalog.library.id) } catch { self.error = ConnectionStore.recovery(for: error) } }
    }
    private var canAccessExplicitContent: Bool {
        if case .content(let content) = catalog.state { return content.user.permissions.accessExplicitContent == true }
        return false
    }
    private func select(_ filter: String?) { presented = false; Task { await catalog.changeFilter(filter) } }
    private func option(_ title: String, group: String, value: String) -> some View {
        Button(title) { select(group + "." + Data(value.utf8).base64EncodedString()) }
    }
    @ViewBuilder private func group(_ title: String, key: String, values: [String]) -> some View {
        if !values.isEmpty {
            NavigationLink(title, destination: ShelfList { ForEach(values, id: \.self) { option($0, group: key, value: $0) } }.navigationTitle(title))
        }
    }
    @ViewBuilder private func namedGroup(_ title: String, key: String, values: [SearchResponse.AuthorMatch]) -> some View {
        if !values.isEmpty {
            NavigationLink(title, destination: ShelfList { ForEach(values) { option($0.name, group: key, value: $0.id) } }.navigationTitle(title))
        }
    }
}
