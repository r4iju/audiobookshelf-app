import SwiftUI

@main struct AudiobookshelfNativeApp: App {
    @StateObject private var connection: ConnectionStore

    init() {
        let vault = KeychainCredentials()
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            try? vault.clear()
            UserDefaults.standard.removeObject(forKey: "previewLibrary")
            UserDefaults.standard.removeObject(forKey: "previewServer")
            UserDefaults.standard.removeObject(forKey: "previewUsername")
        }
        #endif
        _connection = StateObject(wrappedValue: ConnectionStore(api: APIClient(store: vault)))
    }

    var body: some Scene {
        WindowGroup {
            ConnectionRoot().environmentObject(connection)
                .accentColor(ShelfStyle.accent)
                .onAppear { Task { await connection.restore() } }
        }
    }
}
