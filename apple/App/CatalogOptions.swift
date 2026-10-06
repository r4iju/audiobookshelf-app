import SwiftUI

struct CatalogFilterOptions: View {
    @ObservedObject var catalog: CatalogStore
    @Binding var presented: Bool
    @State private var data: LibraryFilters?
    @State private var error: String?
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        CatalogNavigation {
            ShelfList {
                if let error { Text(error).foregroundColor(.red); Button(l10n("Retry filters")) { load() } }
                else if let data {
                    Button(l10n("All titles")) { select(nil) }
                    group(l10n("Genres"), key: "genres", values: data.genres ?? [])
                    group(l10n("Tags"), key: "tags", values: data.tags ?? [])
                    namedGroup(l10n("Authors"), key: "authors", values: data.authors ?? [])
                    namedGroup(l10n("Series"), key: "series", values: data.series ?? [])
                    group(l10n("Narrators"), key: "narrators", values: data.narrators ?? [])
                    group(l10n("Languages"), key: "languages", values: data.languages ?? [])
                    if catalog.library.mediaType == "book" {
                        NavigationLink(l10n("Progress"), destination: ShelfList {
                            option(l10n("Finished"), group: "progress", value: "finished")
                            option(l10n("In progress"), group: "progress", value: "in-progress")
                            option(l10n("Not started"), group: "progress", value: "not-started")
                            option(l10n("Not finished"), group: "progress", value: "not-finished")
                        }.navigationTitle(l10n("Progress")))
                        NavigationLink(l10n("Ebooks"), destination: ShelfList {
                            option(l10n("Has ebook"), group: "ebooks", value: "ebook")
                            option(l10n("Has supplementary ebook"), group: "ebooks", value: "supplementary")
                        }.navigationTitle(l10n("Ebooks")))
                        Button(l10n("No series")) { select("series." + Data("no-series".utf8).base64EncodedString()) }
                        Button(l10n("Items with issues")) { select("issues") }
                    }
                    Button(l10n("Open RSS feeds")) { select("feed-open") }
                    if canAccessExplicitContent { Button(l10n("Explicit content")) { select("explicit") } }
                } else { ProgressView(l10n("Opening filters…")) }
            }.navigationTitle(l10n("Filters")).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { presented = false } } }
        }.onAppear { load() }
    }
    private func load() {
        error = nil
        Task { do { data = try await catalog.api.filters(libraryID: catalog.library.id) } catch { self.error = ConnectionStore.recovery(for: error) } }
    }
    private var canAccessExplicitContent: Bool {
        if case .content(let content) = catalog.state { return content.user.permissions.accessExplicitContent == true }
        return false
    }
    private func select(_ filter: String?) { NativeHaptic.impact("filter"); presented = false; Task { await catalog.changeFilter(filter) } }
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
