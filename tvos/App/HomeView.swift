import SwiftUI

extension View {
    func catalogRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .item(let item): ItemDetailView(item: item)
            case .episode(let item, let episodeID): EpisodeDetailView(item: item, episodeID: episodeID)
            case .author(let author): AuthorView(author: author)
            case .series(let series): SeriesView(series: series)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.nativeStrings) private var l10n

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    if let error = player.error, player.session == nil {
                        Label(error, systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                            .accessibilityIdentifier("sync-error")
                    }
                    if let error = catalog.catalogError {
                        StatusMessage(text: error) { Task { await catalog.loadCatalog() } }
                    } else if catalog.shelves.isEmpty {
                        if catalog.loadingCatalog { ProgressView(l10n("Loading your library…")).frame(maxWidth: .infinity).padding(120) }
                        else { Text(l10n("Nothing to continue yet. Choose a library above to start listening.")).font(.title3).foregroundStyle(.secondary).padding(80) }
                    }
                    ForEach(catalog.shelves) { shelf in
                        VStack(alignment: .leading, spacing: 20) {
                            Text(title(shelf)).font(.title3.bold())
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 48) {
                                    ForEach(shelf.items) { item in
                                        NavigationLink(value: Route.to(item)) { ItemTile(item: item) }
                                            .buttonStyle(.card)
                                            .accessibilityIdentifier("\(shelf.shelfID).\(item.id)")
                                    }
                                }
                                .padding(.vertical, 30)
                            }
                            .scrollClipDisabled()
                        }
                        .focusSection()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .catalogRoutes()
        }
        .onAppear { Task { await catalog.refreshProgress() } }
    }

    private func title(_ shelf: HomeShelf) -> String {
        let name: String
        switch shelf.shelfID {
        case "continue-listening": name = l10n("Continue Listening")
        case "continue-series": name = l10n("Continue Series")
        case "recently-added": name = l10n("Recently Added")
        case "listen-again": name = l10n("Listen Again")
        case "discover": name = l10n("Discover")
        case "newest-episodes", "episodes-recently-added": name = l10n("Newest Episodes")
        default: name = shelf.shelfID.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
        return shelf.libraryName.map { name + " · " + $0 } ?? name
    }
}
