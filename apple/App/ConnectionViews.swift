import SwiftUI

enum ShelfStyle {
    static let accent = Color(red: 0.80, green: 0.31, blue: 0.17)
    static let background = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
}

struct ConnectionRoot: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        Group {
            switch connection.screen {
            case .connection(let error): ConnectionForm(error: error)
            case .loading:
                VStack(spacing: 18) { ProgressView(); Text("Opening your library…").font(.headline); Button("Open downloads") { downloads.presented = true } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .libraries(let libraries): LibraryChooser(libraries: libraries)
            case .shelf(let library): ConnectedLibrary(library: library)
            }
        }.background(ShelfStyle.background.edgesIgnoringSafeArea(.all))
            .sheet(isPresented: $connection.savedConnectionsPresented) { SavedConnectionsView().environmentObject(connection) }
            .overlay(Group {
                if let error = connection.managementError {
                    HStack {
                        Text(error).font(.callout)
                        Button("Dismiss") { connection.managementError = nil }
                    }.padding().background(ShelfStyle.card).cornerRadius(16).padding()
                }
            }, alignment: .top)
    }
}

struct ConnectionForm: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    let error: String?
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "books.vertical.fill").font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white).frame(width: 64, height: 64)
                    .background(ShelfStyle.accent).cornerRadius(20)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Make room for\na good story.").font(.system(size: 40, weight: .bold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your books. Your server.\nListen wherever the day takes you.").font(.body).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    field("Server address") {
                        TextField("https://audiobookshelf.nginx.lan", text: $connection.server)
                            .keyboardType(.URL).textContentType(.URL).autocapitalization(.none).disableAutocorrection(true)
                            .accessibilityIdentifier("server")
                    }
                    field("Username") {
                        TextField("Username", text: $connection.username).textContentType(.username)
                            .autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("username")
                    }
                    field("Password") {
                        SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("password")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("connection-error")
                    }
                    Button {
                        let secret = password
                        password = ""
                        Task { await connection.connect(server: connection.server, username: connection.username, password: secret) }
                    } label: {
                        HStack { Text("Connect to your library").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }
                            .padding(18).foregroundColor(.white).background(ShelfStyle.accent).cornerRadius(16)
                    }.disabled(connection.server.isEmpty || connection.username.isEmpty).accessibilityIdentifier("connect")
                    if !downloads.visible.isEmpty { Button("Open downloads") { downloads.presented = true } }
                    Button("Sign in with OpenID") {
                        password = ""
                        Task { await connection.connectWithOpenID() }
                    }.disabled(connection.server.isEmpty).accessibilityIdentifier("openid-sign-in")
                }.padding(24).background(ShelfStyle.card).cornerRadius(26)
                Text("Connect directly to Audiobookshelf. Local HTTP and trusted HTTPS servers are supported.")
                    .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if connection.api.credentials != nil {
                    Button("Cancel") { Task { await connection.cancelConnection() } }
                }
                if !connection.savedConnections.isEmpty {
                    Button("Downloads") { downloads.presented = true }
                        Button("Saved connections") { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                }
            }.frame(maxWidth: 480).padding(24).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("connection-screen")
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            content().padding(14).background(ShelfStyle.background).cornerRadius(12)
        }
    }
}

struct LibraryChooser: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    let libraries: [Library]
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Find your next chapter.").font(.largeTitle.bold())
                    Text("Choose a library to get started.").foregroundColor(.secondary)
                    ForEach(libraries) { library in
                        Button { connection.select(library) } label: {
                            HStack(spacing: 18) {
                                Image(systemName: library.mediaType == "podcast" ? "mic.fill" : "books.vertical.fill")
                                    .font(.title2).foregroundColor(ShelfStyle.accent).frame(width: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name).font(.headline).foregroundColor(.primary)
                                    Text(library.mediaType == "podcast" ? "Podcasts" : "Audiobooks & reading").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }.padding(22).background(ShelfStyle.card).cornerRadius(20)
                        }.accessibilityIdentifier("library-\(library.id)")
                    }
                    if libraries.isEmpty { Text("No libraries are available to this account. Ask your server administrator for access.").foregroundColor(.secondary) }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.navigationTitle("Your libraries")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Downloads") { downloads.presented = true }
                        Button("Saved connections") { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                        Button("Sign out") { connection.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }.accessibilityIdentifier("account")
                } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct SavedConnectionsView: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var connection: ConnectionStore
    var body: some View {
        NavigationView {
            List {
                ForEach(connection.savedConnections) { saved in
                    Button { Task { await connection.switchConnection(saved.id) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.username).font(.headline).foregroundColor(.primary)
                            Text(saved.server).font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("connection-" + saved.server)
                        .accessibilityLabel(saved.username + " on " + saved.server)
                }
                Button("Add server") { connection.addServer() }
            }.navigationTitle("Saved connections")
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { connection.savedConnectionsPresented = false }
                } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
