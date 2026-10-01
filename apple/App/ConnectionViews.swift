import SwiftUI

enum ShelfStyle {
    static let accent = Color(red: 0.80, green: 0.31, blue: 0.17)
}

struct ConnectionRoot: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        Group {
            switch connection.screen {
            case .connection(let error): ConnectionForm(error: error)
            case .loading:
                VStack(spacing: 18) { ProgressView(); Text(l10n("Opening your library…")).font(.headline); Button(l10n("Open downloads")) { downloads.presented = true } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .libraries(let libraries): LibraryChooser(libraries: libraries)
            case .shelf(let library): ConnectedLibrary(library: library)
            }
        }.background(appearance.background.edgesIgnoringSafeArea(.all))
            .sheet(isPresented: $connection.savedConnectionsPresented) { SavedConnectionsView().environmentObject(connection) }
            .overlay(Group {
                if let error = connection.managementError {
                    HStack {
                        Text(error).font(.callout)
                        Button(l10n("Dismiss")) { connection.managementError = nil }
                    }.padding().background(appearance.card).cornerRadius(16).padding()
                }
            }, alignment: .top)
    }
}

private enum ConnectionFormPanel: String, Identifiable {
    case migration, diagnostics
    var id: String { rawValue }
}

struct ConnectionForm: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    let error: String?
    @State private var password = ""
    @State private var panel: ConnectionFormPanel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "books.vertical.fill").font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white).frame(width: 64, height: 64)
                    .background(ShelfStyle.accent).cornerRadius(20)
                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n("Make room for\na good story.")).font(.system(size: 40, weight: .bold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l10n("Your books. Your server.\nListen wherever the day takes you.")).font(.body).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    field(l10n("Server address")) {
                        TextField("https://audiobookshelf.nginx.lan", text: $connection.server)
                            .keyboardType(.URL).textContentType(.URL).autocapitalization(.none).disableAutocorrection(true)
                            .accessibilityIdentifier("server")
                    }
                    field(l10n("Username")) {
                        TextField(l10n("Username"), text: $connection.username).textContentType(.username)
                            .autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("username")
                    }
                    field(l10n("Password")) {
                        SecureField(l10n("Password"), text: $password).textContentType(.password).accessibilityIdentifier("password")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("connection-error")
                    }
                    Button {
                        NativeHaptic.impact("connect")
                        let secret = password
                        password = ""
                        Task { await connection.connect(server: connection.server, username: connection.username, password: secret) }
                    } label: {
                        HStack { Text(l10n("Connect to your library")).fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }
                            .padding(18).foregroundColor(.white).background(ShelfStyle.accent).cornerRadius(16)
                    }.disabled(connection.server.isEmpty || connection.username.isEmpty).accessibilityIdentifier("connect")
                    if !downloads.visible.isEmpty { Button(l10n("Open downloads")) { downloads.presented = true } }
                    Button(l10n("Sign in with OpenID")) {
                        password = ""
                        Task { await connection.connectWithOpenID() }
                    }.disabled(connection.server.isEmpty).accessibilityIdentifier("openid-sign-in")
                }.padding(24).background(appearance.card).cornerRadius(26)
                Button(l10n("Import previous app data")) { NativeHaptic.impact("migration"); panel = .migration }
                Text(l10n("Connect directly to Audiobookshelf. Local HTTP and trusted HTTPS servers are supported."))
                    .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if connection.api.credentials != nil {
                    Button(l10n("Cancel")) { Task { await connection.cancelConnection() } }
                }
                Button(l10n("Diagnostics")) { panel = .diagnostics }.accessibilityIdentifier("connection-diagnostics")
                if !connection.savedConnections.isEmpty {
                    Button(l10n("Downloads")) { downloads.presented = true }
                        Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                }
            }.frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("connection-screen")
            .sheet(item: $panel) { active in
                NavigationView {
                    Group {
                        switch active {
                        case .migration: NativeMigrationImport()
                        case .diagnostics: NativeDiagnosticsView()
                        }
                    }.toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { panel = nil } } }
                }.navigationViewStyle(StackNavigationViewStyle()).nativeLocalization()
            }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            content().padding(14).background(appearance.background).cornerRadius(12)
        }
    }
}

struct LibraryChooser: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    let libraries: [Library]
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(l10n("Find your next chapter.")).font(.largeTitle.bold())
                    Text(l10n("Choose a library to get started.")).foregroundColor(.secondary)
                    ForEach(libraries) { library in
                        Button { NativeHaptic.impact("library"); connection.select(library) } label: {
                            HStack(spacing: 18) {
                                Image(systemName: library.mediaType == "podcast" ? "mic.fill" : "books.vertical.fill")
                                    .font(.title2).foregroundColor(ShelfStyle.accent).frame(width: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name).font(.headline).foregroundColor(.primary)
                                    Text(l10n(library.mediaType == "podcast" ? "Podcasts" : "Audiobooks & reading")).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }.padding(22).background(appearance.card).cornerRadius(20)
                        }.accessibilityIdentifier("library-\(library.id)")
                    }
                    if libraries.isEmpty { Text(l10n("No libraries are available to this account. Ask your server administrator for access.")).foregroundColor(.secondary) }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.navigationTitle(l10n("Your libraries"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(l10n("Downloads")) { downloads.presented = true }
                        Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                        Button(l10n("Sign out")) { NativeHaptic.impact("sign-out"); connection.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }.accessibilityIdentifier("account")
                } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct SavedConnectionsView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        NavigationView {
            ShelfList {
                ForEach(connection.savedConnections) { saved in
                    Button { NativeHaptic.impact("connect"); Task { await connection.switchConnection(saved.id) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.username).font(.headline).foregroundColor(.primary)
                            Text(saved.server).font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("connection-" + saved.server)
                        .accessibilityLabel(l10n("{0} on {1}", saved.username, saved.server))
                }
                Button(l10n("Add server")) { NativeHaptic.impact("add-server"); connection.addServer() }
            }.navigationTitle(l10n("Saved connections"))
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button(l10n("Done")) { connection.savedConnectionsPresented = false }
                } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
