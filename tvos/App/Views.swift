import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: TVPlayer
    @State private var showPlayer = false
    @State private var showReauthentication = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            if store.signedIn {
                NavigationStack {
                    LibraryView(showPlayer: $showPlayer)
                        .navigationDestination(for: LibraryItem.self) { item in ItemView(item: item, showPlayer: $showPlayer) }
                }
            } else { SignInView() }
        }
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
        .sheet(isPresented: $showReauthentication) {
            SignInView(reauthenticating: true, onAuthenticated: { player.authenticationRestored() })
        }
        .onChange(of: player.needsSignIn) { _, needed in
            if needed { store.needsSignIn = true }
        }
        .alert("Please sign in again", isPresented: $store.needsSignIn) {
            Button("Sign in") {
                player.pause()
                showReauthentication = true
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The server no longer accepts this login.") }
    }
}

struct SignInView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var reauthenticating = false
    var onAuthenticated: () -> Void = {}
    @State private var server = UserDefaults.standard.string(forKey: "lastServer") ?? ""
    @State private var username = UserDefaults.standard.string(forKey: "lastUsername") ?? ""
    @State private var password = ""

    var body: some View {
        HStack(spacing: 110) {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "books.vertical.fill").font(.system(size: 88)).foregroundStyle(.orange)
                Text("Your library.\nOn the big screen.").font(.system(size: 58, weight: .bold))
                Text("Audiobookshelf").font(.title2).foregroundStyle(.secondary)
                Text("Connect to your Audiobookshelf server to listen to your audiobooks and podcasts.")
                    .foregroundStyle(.secondary).frame(maxWidth: 480, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 22) {
                Text("Connect to your server").font(.title2.bold())
                TextField("Server URL · https://books.example.com", text: $server)
                    .textContentType(.URL).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("serverURL")
                    .disabled(reauthenticating)
                TextField("Username", text: $username)
                    .textContentType(.username).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("username")
                    .disabled(reauthenticating)
                SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("password")
                if let error = store.error { Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Button {
                    Task {
                        await store.login(server: server.trimmingCharacters(in: .whitespacesAndNewlines), username: username, password: password)
                        if store.signedIn && store.error == nil {
                            password = ""
                            onAuthenticated()
                            if reauthenticating { dismiss() }
                        }
                    }
                } label: {
                    HStack { if store.loading { ProgressView() }; Text(store.loading ? "Connecting…" : "Connect") }.frame(maxWidth: .infinity)
                }
                .disabled(store.loading || server.isEmpty || username.isEmpty)
                .accessibilityIdentifier("connect")
                Text("Use your iPhone’s Apple TV Remote keyboard for easier typing. Local HTTP servers are supported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 560)
        }
        .padding(80)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: TVPlayer
    @Binding var showPlayer: Bool
    @State private var query = ""
    @State private var signOutError: String?
    private var visible: [LibraryItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                HStack {
                    Label("Audiobookshelf", systemImage: "books.vertical.fill").font(.title.bold())
                    Spacer()
                    if player.session != nil {
                        Button { showPlayer = true } label: { Label("Now playing", systemImage: "waveform") }
                    }
                    Button("Sign out") {
                        Task {
                            do { try await player.stop(); store.signOut() }
                            catch {
                                if error as? APIError == .signInRequired { store.needsSignIn = true }
                                else { signOutError = error.localizedDescription }
                            }
                        }
                    }.disabled(player.preparing || player.seeking)
                }
                if !store.libraries.isEmpty {
                    HStack(spacing: 20) {
                        ForEach(store.libraries) { library in
                            Button {
                                Task { await store.select(library) }
                            } label: {
                                Label(library.name, systemImage: library.mediaType == "podcast" ? "mic.fill" : "book.fill")
                                    .foregroundStyle(store.selectedLibrary == library ? .orange : .primary)
                            }
                        }
                    }
                }
                TextField("Filter loaded titles or authors", text: $query).frame(maxWidth: 750)
                    .autocorrectionDisabled().accessibilityIdentifier("libraryFilter")
                if !query.isEmpty && store.hasMore {
                    Text("Filtering the loaded titles. Load more below to include the rest of the library.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.error {
                    HStack {
                        Text(error).foregroundStyle(.orange)
                        Button("Retry") {
                            Task {
                                if store.selectedLibrary == nil { await store.loadLibraries() }
                                else { await store.loadMore() }
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 260), spacing: 40)], alignment: .leading, spacing: 45) {
                    ForEach(visible) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 12) {
                                CoverView(itemID: item.id).frame(width: 230, height: 230).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(item.title).font(.system(size: 26, weight: .semibold)).lineLimit(2).frame(height: 68, alignment: .topLeading)
                                Text(item.author).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 230)
                        }.buttonStyle(.card)
                    }
                }
                if store.loading { ProgressView("Loading library…").frame(maxWidth: .infinity) }
                else if visible.isEmpty && store.error == nil {
                    Text(query.isEmpty ? "This library is empty." : "No loaded titles match your filter.").foregroundStyle(.secondary)
                }
                if store.hasMore && !store.loading {
                    Button("Load more titles") { Task { await store.loadMore() } }.accessibilityIdentifier("loadMore")
                }
            }.padding(.horizontal, 70).padding(.vertical, 45)
        }
        .task { if store.libraries.isEmpty { await store.loadLibraries() } }
        .alert("Could not save playback progress", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(signOutError ?? "") }
    }
}

struct CoverView: View {
    @EnvironmentObject private var store: LibraryStore
    let itemID: String
    @State private var cover: UIImage?
    var body: some View {
        ZStack {
            Color(red: 0.22, green: 0.18, blue: 0.13)
            if let cover { Image(uiImage: cover).resizable().scaledToFill() }
            else { Image(systemName: "book.closed.fill").font(.system(size: 66)).foregroundStyle(.orange.opacity(0.8)) }
        }
        .clipped()
        .task(id: itemID) { cover = await store.cover(itemID: itemID) }
    }
}

struct ItemView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: TVPlayer
    let item: LibraryItem
    @Binding var showPlayer: Bool
    @State private var detail: LibraryItem?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 65) {
                CoverView(itemID: item.id).frame(width: 380, height: 380).clipShape(RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 24) {
                    Text(item.title).font(.largeTitle.bold())
                    Text(item.author).font(.title3).foregroundStyle(.secondary)
                    if let duration = detail?.media.duration { Text(Self.duration(duration)).foregroundStyle(.secondary) }
                    if loading { ProgressView("Loading details…") }
                    if let error { Text(error).foregroundStyle(.orange); Button("Retry") { Task { await load() } } }
                    if item.mediaType == "podcast" {
                        ForEach(detail?.media.episodes ?? []) { episode in
                            Button {
                                Task { await player.start(item: detail ?? item, episode: episode); if player.session != nil { showPlayer = true } }
                            } label: {
                                HStack { Image(systemName: "play.fill"); Text(episode.title); Spacer(); if let duration = episode.duration { Text(Self.duration(duration)) } }
                            }.disabled(player.preparing || player.seeking)
                        }
                        if !loading && error == nil && (detail?.media.episodes ?? []).isEmpty { Text("No downloaded episodes are available.") }
                    } else {
                        Button {
                            Task { await player.start(item: detail ?? item); if player.session != nil { showPlayer = true } }
                        } label: { Label(player.preparing ? "Preparing…" : "Play / Resume", systemImage: "play.fill") }
                            .disabled(player.preparing || player.seeking || loading || detail == nil)
                    }
                    if let failure = player.error { Text(failure).foregroundStyle(.orange) }
                    if let description = detail?.media.metadata.description {
                        Text(Self.plainText(description)).font(.body).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(70)
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; error = nil
        do { detail = try await store.api.item(id: item.id) }
        catch { self.error = error.localizedDescription; store.show(error) }
        loading = false
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(seconds.isFinite ? seconds : 0, 0)) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showChapters = false

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Text("NOW PLAYING").font(.caption).tracking(4).foregroundStyle(.orange)
                Spacer()
                Button("Back to library") { dismiss() }
            }
            HStack(spacing: 65) {
                if let id = player.itemID { CoverView(itemID: id).frame(width: 340, height: 340).clipShape(RoundedRectangle(cornerRadius: 20)) }
                VStack(alignment: .leading, spacing: 22) {
                    Text(player.title).font(.largeTitle.bold()).lineLimit(3)
                    Text(player.author).font(.title3).foregroundStyle(.secondary)
                    if let session = player.session {
                        ProgressView(value: min(player.currentTime, session.duration), total: max(session.duration, 1)).tint(.orange)
                        HStack {
                            Text(clock(player.currentTime))
                            Spacer()
                            Text("−" + clock(max(session.duration - player.currentTime, 0)))
                        }.font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 25) {
                        Button { Task { await player.skip(-30) } } label: { Image(systemName: "gobackward.30") }
                        Button { player.toggle() } label: { Label(player.playing ? "Pause" : "Play", systemImage: player.playing ? "pause.fill" : "play.fill") }
                        Button { Task { await player.skip(30) } } label: { Image(systemName: "goforward.30") }
                    }.disabled(player.seeking || player.preparing)
                    HStack(spacing: 25) {
                        Button("Speed · \(player.speed, specifier: "%.2g")×") {
                            let rates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
                            let index = rates.firstIndex(of: player.speed) ?? 1
                            player.speed = rates[(index + 1) % rates.count]
                            player.changeSpeed()
                        }
                        if !(player.session?.chapters ?? []).isEmpty { Button("Chapters") { showChapters = true } }
                    }
                }.frame(maxWidth: .infinity)
            }
            if let error = player.error {
                HStack {
                    Text(error).foregroundStyle(.orange)
                    if player.needsSignIn {
                        Button("Sign in again") { dismiss(); store.needsSignIn = true }
                    } else {
                        Button("Retry saving progress") { player.error = nil; player.sync() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(70)
        .onPlayPauseCommand { player.toggle() }
        .sheet(isPresented: $showChapters) {
            List(player.session?.chapters ?? []) { chapter in
                Button("\(chapter.title) · \(clock(chapter.start))") {
                    Task {
                        do { try await player.seek(to: chapter.start, autoplay: player.playing); showChapters = false }
                        catch { player.error = error.localizedDescription }
                    }
                }
            }.padding(50)
        }
    }
    private func clock(_ seconds: Double) -> String {
        let value = Int(max(seconds.isFinite ? seconds : 0, 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}
