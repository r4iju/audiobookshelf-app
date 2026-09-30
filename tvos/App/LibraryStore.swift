import SwiftUI

@MainActor final class LibraryStore: ObservableObject {
    let api: APIClient
    @Published var signedIn: Bool
    @Published var libraries: [Library] = []
    @Published var selectedLibrary: Library?
    @Published var items: [LibraryItem] = []
    @Published var loading = false
    @Published var hasMore = false
    @Published var error: String?
    @Published var needsSignIn = false
    private var page = 0
    private var generation = UUID()
    private var covers: [String: UIImage] = [:]

    init(api: APIClient) {
        self.api = api
        signedIn = api.credentials != nil
    }

    func login(server: String, username: String, password: String) async {
        loading = true
        error = nil
        do {
            try await api.login(server: server, username: username, password: password)
            needsSignIn = false
            signedIn = true
            UserDefaults.standard.set(server, forKey: "lastServer")
            UserDefaults.standard.set(username, forKey: "lastUsername")
        } catch { show(error) }
        loading = false
    }

    func loadLibraries() async {
        let requestGeneration = generation
        loading = true
        do {
            let result = try await api.libraries()
            guard requestGeneration == generation else { return }
            libraries = result
            if let library = libraries.first { await select(library) }
            else { loading = false }
        } catch {
            guard requestGeneration == generation else { return }
            show(error); loading = false
        }
    }

    func select(_ library: Library) async {
        generation = UUID()
        selectedLibrary = library
        items = []
        page = 0
        hasMore = true
        loading = false
        await loadMore()
    }

    func loadMore() async {
        guard !loading, hasMore, let library = selectedLibrary else { return }
        let requestGeneration = generation
        loading = true
        error = nil
        do {
            let response = try await api.items(libraryID: library.id, page: page)
            guard requestGeneration == generation else { return }
            let existing = Set(items.map(\.id))
            items += response.results.filter { !existing.contains($0.id) }
            page += 1
            hasMore = page * 60 < response.total && !response.results.isEmpty
        } catch {
            guard requestGeneration == generation else { return }
            show(error)
        }
        loading = false
    }

    func cover(itemID: String) async -> UIImage? {
        if let cached = covers[itemID] { return cached }
        guard let data = try? await api.coverData(itemID: itemID), let image = UIImage(data: data) else { return nil }
        if covers.count >= 160 { covers.removeAll() }
        covers[itemID] = image
        return image
    }

    func signOut() {
        do {
            try api.signOut()
            generation = UUID()
            libraries = []; items = []; covers = [:]; selectedLibrary = nil
            signedIn = false; needsSignIn = false; loading = false
        } catch { show(error) }
    }

    func show(_ failure: Error) {
        if failure as? APIError == .signInRequired { needsSignIn = true }
        error = failure.localizedDescription
    }
}
