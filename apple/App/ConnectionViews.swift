import SwiftUI

// Every text colour here reaches 4.5:1 (WCAG 1.4.3) on the light, dark and black surfaces; the system secondary label
// does not in light, and one accent cannot in both light and dark. The accent is the asset catalog's global accent so
// sheets and full screen covers, which do not inherit .accentColor, use it too.
enum ShelfStyle {
    static let accent = Color("AccentColor")
    /// Fill behind white text and symbols: the light accent in every appearance.
    static let accentFill = Color(UIColor(named: "AccentColor")!.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    static let secondaryText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.secondaryLabel.resolvedColor(with: traits) : UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1)
    })
}

struct ConnectionRoot: View {
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        Group {
            switch connection.screen {
            case .connection(let error): PlaybackContainer(content: ConnectionForm(error: error))
            case .loading:
                PlaybackContainer(content: VStack(spacing: 24) {
                    ProgressView().accessibilityLabel(l10n("Opening your library…"))
                    Text(l10n("Opening your library…")).font(.headline)
                    Button(l10n("Open downloads")) { downloads.presented = true }.nativeGlassButton()
                }.padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            case .libraries(let libraries): PlaybackContainer(content: LibraryChooser(libraries: libraries))
            case .shelf(let library): NativeShell(library: library)
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
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "books.vertical.fill")
                            .font(.largeTitle).foregroundColor(ShelfStyle.accent).accessibilityHidden(true)
                        Text(l10n("Make room for\na good story."))
                            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(l10n("Your books. Your server.\nListen wherever the day takes you."))
                            .font(.body).foregroundColor(ShelfStyle.secondaryText)
                    }.padding(.vertical, 12)
                }.listRowBackground(appearance.card)
                Section {
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
                        Label { Text(error).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .font(.callout).foregroundColor(.primary).accessibilityIdentifier("connection-error")
                            .accessibilityElement(children: .combine)
                    }
                }.listRowBackground(appearance.card)
                Section {
                    Button {
                        NativeHaptic.impact("connect")
                        let secret = password
                        password = ""
                        Task { await connection.connect(server: connection.server, username: connection.username, password: secret) }
                    } label: {
                        Label(l10n("Connect to your library"), systemImage: "arrow.right")
                            .font(.headline).frame(maxWidth: .infinity).padding(16)
                            .nativeGlassControl(tint: ShelfStyle.accentFill)
                    }.buttonStyle(PlainButtonStyle())
                        .disabled(connection.server.isEmpty || connection.username.isEmpty).accessibilityIdentifier("connect")
                    Button(l10n("Sign in with OpenID")) {
                        password = ""
                        Task { await connection.connectWithOpenID() }
                    }.disabled(connection.server.isEmpty).accessibilityIdentifier("openid-sign-in")
                    if connection.api.credentials != nil {
                        Button(l10n("Cancel")) { Task { await connection.cancelConnection() } }
                    }
                }.listRowBackground(appearance.card)
                Section(footer: Text(l10n("Connect directly to Audiobookshelf. Local HTTP and trusted HTTPS servers are supported."))) {
                    Button(l10n("Import previous app data")) { NativeHaptic.impact("migration"); panel = .migration }
                    Button(l10n("Diagnostics")) { panel = .diagnostics }.accessibilityIdentifier("connection-diagnostics")
                    if !connection.savedConnections.isEmpty {
                        Button(l10n("Downloads")) { downloads.presented = true }
                        Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                    }
                }
            }.listRowBackground(appearance.card)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                .nativeConnectionFormBackground(appearance.background)
                .navigationTitle(l10n("Connect"))
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("connection-screen")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !downloads.visible.isEmpty {
                            Button { downloads.presented = true } label: {
                                Label(l10n("Open downloads"), systemImage: "arrow.down.circle")
                            }.accessibilityLabel(l10n("Open downloads"))
                        }
                    }
                }
        }.navigationViewStyle(StackNavigationViewStyle())
            .sheet(item: $panel) { active in
                NativeNavigation {
                    Group {
                        switch active {
                        case .migration: NativeMigrationImport()
                        case .diagnostics: NativeDiagnosticsView()
                        }
                    }.toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { panel = nil } } }
                }.listeningSheet().nativeLocalization()
            }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).fontWeight(.semibold).foregroundColor(ShelfStyle.secondaryText)
            content().accessibilityLabel(title).padding(.vertical, 6)
        }
    }
}

private extension View {
    @ViewBuilder func nativeConnectionFormBackground(_ color: Color) -> some View {
        if #available(iOS 16, *) {
            self.scrollContentBackground(.hidden).background(color)
        } else {
            self
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
        NativeNavigation {
            ShelfList {
                Section {
                    Text(l10n("Choose a library to get started.")).foregroundColor(ShelfStyle.secondaryText)
                }
                Section {
                    ForEach(libraries) { library in
                        Button { NativeHaptic.impact("library"); connection.select(library) } label: {
                            HStack(spacing: 18) {
                                Image(systemName: library.mediaType == "podcast" ? "mic.fill" : "books.vertical.fill")
                                    .font(.title2).foregroundColor(ShelfStyle.accent).frame(width: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name).font(.headline).foregroundColor(.primary)
                                    Text(l10n(library.mediaType == "podcast" ? "Podcasts" : "Audiobooks & reading")).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundColor(ShelfStyle.secondaryText)
                            }.padding(.vertical, 10)
                        }.accessibilityIdentifier("library-\(library.id)")
                    }
                    if libraries.isEmpty { Text(l10n("No libraries are available to this account. Ask your server administrator for access.")).foregroundColor(ShelfStyle.secondaryText) }
                }
            }.navigationTitle(l10n("Your libraries"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(l10n("Downloads")) { downloads.presented = true }
                        Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                        Button(l10n("Sign out")) { NativeHaptic.impact("sign-out"); connection.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel(l10n("Account")).accessibilityIdentifier("account")
                } }
        }
    }
}

struct SavedConnectionsView: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        NativeNavigation {
            ShelfList {
                ForEach(connection.savedConnections) { saved in
                    Button { NativeHaptic.impact("connect"); Task { await connection.switchConnection(saved.id) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.username).font(.headline).foregroundColor(.primary)
                            Text(saved.server).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("connection-" + saved.server)
                        .accessibilityLabel(l10n("{0} on {1}", saved.username, saved.server))
                }
            }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Saved connections")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button(l10n("Done")) { connection.savedConnectionsPresented = false }
                }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(l10n("Add server")) { NativeHaptic.impact("add-server"); connection.addServer() }
                    }
                }
        }
    }
}
