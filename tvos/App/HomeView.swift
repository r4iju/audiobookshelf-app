import SwiftUI

extension View {
    func catalogRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .item(let item): ItemDetailView(item: item)
            case .episode(let item, let episodeID): EpisodeDetailView(item: item, episodeID: episodeID)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer

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
                        if catalog.loadingCatalog { ProgressView("Loading your library…").frame(maxWidth: .infinity).padding(120) }
                        else { Text("Nothing to continue yet. Choose a library above to start listening.").font(.title3).foregroundStyle(.secondary).padding(80) }
                    }
                    ForEach(catalog.shelves) { shelf in
                        VStack(alignment: .leading, spacing: 20) {
                            Text(shelf.title).font(.title3.bold())
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

}
