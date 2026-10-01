import SwiftUI

@MainActor final class AudioGroupStore: ObservableObject {
    @Published private(set) var groups: [AudioGroup] = []
    @Published private(set) var selected: AudioGroup?
    @Published private(set) var user: CurrentUser?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var saving = false
    @Published private(set) var starting = false
    let catalog: CatalogStore
    let kind: AudioGroupKind
    private var generation = UUID()
    private var owner: AccountIdentity?
    init(catalog: CatalogStore, kind: AudioGroupKind) { self.catalog = catalog; self.kind = kind }
    var canEdit: Bool { !loading && owner != nil && user != nil && (kind == .playlist || user?.permissions.update == true || user?.canManagePodcasts == true) }
    var canDelete: Bool { !loading && owner != nil && user != nil && (kind == .playlist || user?.permissions.delete == true || user?.canManagePodcasts == true) }
    func save(id: String?, name: String, description: String, members: [AudioGroupMember]) async -> Bool {
        guard !saving, canEdit, let owner else { return false }
        let request = UUID(); generation = request; loading = false; saving = true; error = nil
        defer { if generation == request { saving = false } }
        do {
            let result = try await catalog.api.saveAudioGroup(id: id, libraryID: catalog.library.id, kind: kind, name: name, description: description, members: members, account: owner)
            guard generation == request, try await catalog.api.currentAccount() == owner else { return false }
            selected = result
            if let index = groups.firstIndex(where: { $0.id == result.id }) { groups[index] = result } else { groups.append(result) }
            return true
        } catch { if generation == request { self.error = "Changes could not be completed. Some membership changes may already be saved. " + ConnectionStore.recovery(for: error) }; return false }
    }
    func delete(id: String) async -> Bool {
        guard !saving, canDelete, let owner else { return false }
        let request = UUID(); generation = request; loading = false; saving = true; error = nil
        defer { if generation == request { saving = false } }
        do {
            try await catalog.api.deleteAudioGroup(id: id, kind: kind, account: owner)
            guard generation == request, try await catalog.api.currentAccount() == owner else { return false }
            groups.removeAll { $0.id == id }; selected = nil; return true
        } catch { if generation == request { self.error = ConnectionStore.recovery(for: error) }; return false }
    }
    func load(id: String? = nil) async {
        guard !saving else { return }
        let request = UUID(); generation = request; loading = true; error = nil
        defer { if generation == request { loading = false } }
        do {
            let account = try await catalog.api.currentAccount()
            guard owner == nil || owner == account else { user = nil; groups = []; selected = nil; throw APIError.signInRequired }
            owner = account
            async let currentUser = catalog.api.me()
            if let id {
                let group = try await catalog.api.audioGroup(id: id, kind: kind)
                let user = try await currentUser
                guard generation == request, try await catalog.api.currentAccount() == account else { return }
                selected = group; self.user = user
            } else {
                let page = try await catalog.api.audioGroups(libraryID: catalog.library.id, kind: kind)
                let user = try await currentUser
                guard generation == request, try await catalog.api.currentAccount() == account else { return }
                groups = page.results; self.user = user
            }
        } catch { if generation == request { self.error = ConnectionStore.recovery(for: error) } }
    }
    private func nextChoice(in group: AudioGroup, downloads: NativeDownloads, player: ApplePlayback) throws -> (member: AudioGroupMember, audio: OfflineAudio?)? {
        for member in group.members where member.playable {
            let progress = user?.mediaProgress.first { $0.libraryItemId == member.libraryItemId && $0.episodeId == member.episodeId }
            if let entry = downloads.visible.first(where: { $0.account == owner && $0.state == .ready && !$0.tracks.isEmpty && $0.supplementaryID == nil && $0.media.libraryItemID == member.libraryItemId && $0.media.episodeID == member.episodeId }) {
                let audio = try downloads.audio(entry, progress: progress)
                let serverFinished = progress?.isFinished == true && (progress?.lastUpdate ?? 0) >= audio.serverUpdatedAt
                if try player.hasFinishedOffline(audio, serverFinished: serverFinished) { continue }
                return (member, audio)
            }
            if progress?.isFinished != true { return (member, nil) }
        }
        return nil
    }
    func play(_ group: AudioGroup, player: ApplePlayback, downloads: NativeDownloads) async {
        guard !starting, !loading, !saving, let owner else { return }
        let revision = generation
        guard (try? await catalog.api.currentAccount()) == owner else { error = ConnectionStore.recovery(for: APIError.signInRequired); return }
        guard generation == revision else { return }
        let active = group.members.contains { $0.libraryItemId == player.itemID && $0.episodeId == player.episodeID }
        if active, player.wantsPlayback { player.pause(); return }
        starting = true
        defer { starting = false }
        do {
            guard try await catalog.api.currentAccount() == owner else { throw APIError.signInRequired }
            do {
                let currentUser = try await catalog.api.me()
                guard generation == revision, try await catalog.api.currentAccount() == owner else { throw APIError.signInRequired }
                user = currentUser
            } catch {
                let unreachable: Bool
                if let failure = error as? URLError {
                    unreachable = [.notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost].contains(failure.code)
                } else if case APIError.http(let code) = error {
                    unreachable = (500...599).contains(code)
                } else { unreachable = false }
                guard unreachable, generation == revision, try await catalog.api.currentAccount() == owner,
                      try nextChoice(in: group, downloads: downloads, player: player)?.audio != nil else { throw error }
            }
            guard let choice = try nextChoice(in: group, downloads: downloads, player: player), let item = choice.member.libraryItem else { error = "Every playable title in this group is finished."; return }
            let member = choice.member
            if let audio = choice.audio {
                try await player.resumeOffline(audio)
                return
            }
            if player.itemID == member.libraryItemId, player.episodeID == member.episodeId, player.session != nil { player.resume() }
            else { await player.start(item: item, episode: member.episode) }
        } catch { if generation == revision { self.error = ConnectionStore.recovery(for: error) } }
    }
}

struct AudioGroupList: View {
    @StateObject private var store: AudioGroupStore
    @State private var creating = false
    init(catalog: CatalogStore, kind: AudioGroupKind) { _store = StateObject(wrappedValue: AudioGroupStore(catalog: catalog, kind: kind)) }
    var body: some View {
        List {
            if store.loading { ProgressView("Opening \(store.kind.title.lowercased())…") }
            if let error = store.error { RecoveryCard(message: error) { Task { await store.load() } } }
            ForEach(store.groups) { group in
                NavigationLink(destination: AudioGroupDetails(catalog: store.catalog, kind: store.kind, group: group)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name).font(.headline)
                        Text("\(group.members.count) titles").font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("group-\(group.id)")
            }
            if !store.loading, store.error == nil, store.groups.isEmpty { Text("No \(store.kind.title.lowercased()) yet.").foregroundColor(.secondary) }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(store.kind.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Refresh") { Task { await store.load() } }
                        if store.canEdit { Button("New \(store.kind.singular)") { creating = true } }
                    }
                }
            }
            .sheet(isPresented: $creating) { AudioGroupEditor(store: store, group: nil, presented: $creating) }
            .onAppear { Task { await store.load() } }
    }
}

struct AudioGroupDetails: View {
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var downloads: NativeDownloads
    @StateObject private var store: AudioGroupStore
    @Environment(\.presentationMode) private var presentation
    @State private var editing = false
    @State private var deleting = false
    let initial: AudioGroup
    init(catalog: CatalogStore, kind: AudioGroupKind, group: AudioGroup) {
        initial = group; _store = StateObject(wrappedValue: AudioGroupStore(catalog: catalog, kind: kind))
    }
    var body: some View {
        let group = store.selected ?? initial
        let active = player.wantsPlayback && group.members.contains { $0.libraryItemId == player.itemID && $0.episodeId == player.episodeID }
        List {
            if let error = store.error { RecoveryCard(message: error) { Task { await store.load(id: initial.id) } } }
            if let description = group.description, !description.isEmpty { Text(description).foregroundColor(.secondary) }
            Button("\(active ? "Pause" : "Play") \(store.kind.singular)") { Task { await store.play(group, player: player, downloads: downloads) } }
                .disabled(store.loading || store.saving || store.starting || store.error != nil || player.preparing || !group.members.contains(where: \.playable))
            ForEach(group.members) { member in
                if let item = member.libraryItem {
                    NavigationLink(destination: BookDetails(item: item, catalog: store.catalog, progress: store.user?.mediaProgress.first { $0.libraryItemId == item.id && $0.episodeId == member.episodeId }, episode: member.episode)) {
                        VStack(alignment: .leading, spacing: 6) { Text(member.title).font(.headline); Text(item.author).font(.caption).foregroundColor(.secondary) }.padding(.vertical, 6)
                    }.accessibilityIdentifier("group-member-\(member.id)")
                } else { Text(member.title).foregroundColor(.secondary) }
            }
            if let error = player.error { Text(error).foregroundColor(.red) }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(group.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                    if store.canEdit { Button("Edit \(store.kind.singular)") { editing = true } }
                    Menu {
                        Button("Refresh") { Task { await store.load(id: initial.id) } }
                        if store.canDelete { Button("Delete \(store.kind.singular)") { deleting = true } }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Group actions")
                    }
                }
            }
            .sheet(isPresented: $editing) { AudioGroupEditor(store: store, group: store.selected ?? initial, presented: $editing) }
            .alert(isPresented: $deleting) {
                Alert(title: Text("Delete \(store.kind.singular)?"), message: Text("The audio files stay in your library."), primaryButton: .destructive(Text("Delete")) {
                    Task { if await store.delete(id: initial.id) { presentation.wrappedValue.dismiss() } }
                }, secondaryButton: .cancel())
            }
            .onAppear { Task { await store.load(id: initial.id) } }
    }
}

struct AudioGroupEditor: View {
    @ObservedObject var store: AudioGroupStore
    let group: AudioGroup?
    @Binding var presented: Bool
    @State private var name: String
    @State private var description: String
    @State private var members: [AudioGroupMember]
    @State private var choosing = false
    init(store: AudioGroupStore, group: AudioGroup?, presented: Binding<Bool>) {
        self.store = store; self.group = group; _presented = presented
        _name = State(initialValue: group?.name ?? ""); _description = State(initialValue: group?.description ?? "")
        _members = State(initialValue: group?.members ?? [])
    }
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Name", text: $name).accessibilityIdentifier("group-name")
                    TextField("Description", text: $description).accessibilityIdentifier("group-description")
                }
                Section(header: Text("Listening order")) {
                    ForEach(members) { member in
                        HStack {
                            Text(member.title)
                            Spacer()
                            Button {
                                if let index = members.firstIndex(where: { $0.id == member.id }), index > 0 { members.swapAt(index, index - 1) }
                            } label: { Image(systemName: "arrow.up") }.buttonStyle(BorderlessButtonStyle())
                                .accessibilityLabel("Move \(member.title) up").accessibilityIdentifier("move-up-\(member.id)")
                                .disabled(members.first?.id == member.id)
                            Button { members.removeAll { $0.id == member.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(BorderlessButtonStyle())
                                .accessibilityLabel("Remove \(member.title)").accessibilityIdentifier("remove-\(member.id)")
                                .disabled(store.kind == .playlist && group != nil && members.count == 1)
                        }
                    }
                    Button("Choose titles") { choosing = true }
                    if store.kind == .playlist, group != nil, members.count == 1 { Text("To remove the last title, delete this playlist from its actions menu.").font(.caption).foregroundColor(.secondary) }
                }
                if let error = store.error { Text(error).foregroundColor(.red).accessibilityIdentifier("group-save-error") }
                if store.saving { ProgressView("Saving changes…") }
            }.disabled(store.saving).navigationTitle(group == nil ? "New \(store.kind.singular)" : "Edit \(store.kind.singular)")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { presented = false }.disabled(store.saving) }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save group") {
                            Task { if await store.save(id: group?.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description, members: members) { presented = false } }
                        }.disabled(store.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (members.isEmpty && (group == nil || store.kind == .playlist)))
                    }
                }
                .sheet(isPresented: $choosing) { AudioGroupMemberPicker(catalog: store.catalog, members: $members, presented: $choosing) }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct AudioGroupMemberPicker: View {
    @StateObject private var catalog: CatalogStore
    @Binding var members: [AudioGroupMember]
    @Binding var presented: Bool
    init(catalog: CatalogStore, members: Binding<[AudioGroupMember]>, presented: Binding<Bool>) {
        _catalog = StateObject(wrappedValue: CatalogStore(api: catalog.api, library: catalog.library)); _members = members; _presented = presented
    }
    var body: some View {
        NavigationView {
            List {
                switch catalog.state {
                case .loading: ProgressView("Opening titles…")
                case .failed(let error): RecoveryCard(message: error) { Task { await catalog.reload() } }
                case .content(let content):
                    ForEach(content.items) { item in
                        if item.mediaType == "podcast" {
                            NavigationLink(item.title, destination: AudioGroupEpisodePicker(item: item, api: catalog.api, members: $members))
                        } else {
                            Button {
                                if members.contains(where: { $0.libraryItemId == item.id }) { members.removeAll { $0.libraryItemId == item.id } }
                                else { members.append(AudioGroupMember(libraryItemId: item.id, libraryItem: item, episodeId: nil, episode: nil)) }
                            } label: {
                                HStack { Text(item.title); Spacer(); if members.contains(where: { $0.libraryItemId == item.id }) { Image(systemName: "checkmark") } }
                            }.accessibilityIdentifier("choose-\(item.id)")
                        }
                    }
                    if let error = content.pageError { RecoveryCard(message: error) { Task { await catalog.loadMore() } } }
                    if content.hasMore { Button("More titles") { Task { await catalog.loadMore() } } }
                }
            }.navigationTitle("Choose titles")
                .toolbar { Button("Done choosing") { presented = false } }
                .onAppear { if case .loading = catalog.state { Task { await catalog.reload() } } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct AudioGroupEpisodePicker: View {
    let item: LibraryItem
    let api: APIClient
    @Binding var members: [AudioGroupMember]
    @State private var expanded: LibraryItem?
    @State private var error: String?
    var body: some View {
        List {
            if let error { RecoveryCard(message: error) { Task { await load() } } }
            if let expanded {
                ForEach(expanded.media.episodes ?? []) { episode in
                    Button {
                        if members.contains(where: { $0.episodeId == episode.id && $0.libraryItemId == item.id }) { members.removeAll { $0.episodeId == episode.id && $0.libraryItemId == item.id } }
                        else { members.append(AudioGroupMember(libraryItemId: item.id, libraryItem: expanded, episodeId: episode.id, episode: episode)) }
                    } label: {
                        HStack { Text(episode.title); Spacer(); if members.contains(where: { $0.libraryItemId == item.id && $0.episodeId == episode.id }) { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("choose-episode-\(episode.id)")
                }
            } else if error == nil { ProgressView("Opening episodes…") }
        }.navigationTitle(item.title).onAppear { Task { await load() } }
    }
    private func load() async {
        error = nil
        do {
            let account = try await api.currentAccount()
            let result = try await api.item(id: item.id)
            guard try await api.currentAccount() == account else { return }
            expanded = result
        } catch { self.error = ConnectionStore.recovery(for: error) }
    }
}
