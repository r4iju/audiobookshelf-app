import SwiftUI
import WebKit
import UIKit
import CryptoKit

private struct EPUBPreferences: Codable {
    var theme = "dark"
    var font = "serif"
    var scale = 100.0
    var spacing = 160.0
    var stroke = 0.0
    var spread = "auto"
    var keepAwake = false
    var volume = "enabled"
    var volumeWhileListening = false
}

@MainActor private final class EPUBReading: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    struct Chapter: Identifiable { var id: String { href }; let title: String; let href: String }
    @Published var chapters: [Chapter] = []
    @Published var ready = false
    @Published var error: String?
    @Published var savingError: String?
    @Published var preferences: EPUBPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "previewEPUBPreferences") }
            call("preferences", preferences)
            applyAwakePreference()
            configureVolume()
        }
    }
    let source: ReadingSource
    let api: APIClient
    let store: ReadingStore
    weak var web: WKWebView?
    private let volume = ReaderVolume()
    private var listening = false
    private var active = true
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var shellReady = false
    private var previousIdleTimer: Bool?
    private var payload: Payload?
    private var locationCache: URL?
    private struct Payload: Encodable { let data: String; let location: String?; let preferences: EPUBPreferences; let cache: String? }
    init(source: ReadingSource, api: APIClient, store: ReadingStore) {
        self.source = source; self.api = api; self.store = store
        preferences = UserDefaults.standard.data(forKey: "previewEPUBPreferences").flatMap { try? JSONDecoder().decode(EPUBPreferences.self, from: $0) } ?? EPUBPreferences()
    }
    func attach(_ web: WKWebView) {
        self.web = web
        previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        applyAwakePreference()
        volume.attach(to: web) { [weak self] up in
            guard let self, self.ready else { return }
            self.call("turn", self.preferences.volume == "mirrored" ? up : !up)
        }
        configureVolume()
        web.navigationDelegate = self
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "html", subdirectory: "ReaderAssets") else { error = "The local reader resources are missing."; return }
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        open()
    }
    func open() {
        guard task == nil else { return }
        let id = UUID(); generation = id
        if error != nil { error = nil }
        task = Task {
            defer { if generation == id { task = nil } }
            do {
                if source.fileID == nil {
                    if let progress = source.progress { try store.adopt(progress, account: source.account, itemID: source.itemID, format: "epub") }
                    if source.file == nil { await store.reconcile(api: api, account: source.account, itemID: source.itemID, format: "epub") }
                }
                guard try await api.currentAccount() == source.account else { throw CancellationError() }
                let data: Data
                if let file = source.file { data = try await Task.detached { try Data(contentsOf: file, options: .mappedIfSafe) }.value }
                else { data = try await api.ebookData(itemID: source.itemID, ebook: source.ebook) }
                try Task.checkCancellation()
                guard generation == id, try await api.currentAccount() == source.account else { throw CancellationError() }
                guard data.starts(with: [0x50, 0x4b]) else { throw ReaderFailure.invalid }
                let saved = store.position(account: source.account, itemID: source.itemID, format: "epub", fileID: source.fileID)
                let scope = try JSONEncoder().encode(source.account)
                let key = SHA256.hash(data: scope + data).map { String(format: "%02x", $0) }.joined()
                locationCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("NativeReading", isDirectory: true).appendingPathComponent("epubjs-0.3.88-" + key + ".json")
                let cached = locationCache.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                payload = Payload(data: data.base64EncodedString(), location: saved?.location, preferences: preferences, cache: cached)
                if shellReady, let payload { call("openBook", payload) }
            } catch { if !(error is CancellationError), generation == id { self.error = error.localizedDescription } }
        }
    }
    func context(listening: Bool, active: Bool) {
        self.listening = listening; self.active = active; configureVolume()
    }
    private func configureVolume() {
        volume.enabled(web != nil && active && preferences.volume != "none" && (preferences.volumeWhileListening || !listening))
    }
    private func applyAwakePreference() {
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer || preferences.keepAwake }
    }
    func detach() {
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        previousIdleTimer = nil
        volume.detach()
        generation = UUID(); task?.cancel(); task = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
        web?.stopLoading(); web = nil
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? [String: Any] else { return }
        if value["shellReady"] as? Bool == true { shellReady = true; if let payload { call("openBook", payload) } }
        if value["ready"] as? Bool == true { ready = true; error = nil }
        if let cache = value["cache"] as? String, cache.utf8.count < 4_000_000, let locationCache {
            do {
                try FileManager.default.createDirectory(at: locationCache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(cache.utf8).write(to: locationCache, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { /* Derived locations can be regenerated without changing the saved passage. */ }
        }
        if let failure = value["error"] as? String { error = "This EPUB could not be opened: " + failure }
        if let items = value["chapters"] as? [[String: String]] {
            chapters = items.compactMap { item in guard let title = item["title"], let href = item["href"] else { return nil }; return Chapter(title: title, href: href) }
        }
        if let location = value["location"] as? String, location.hasPrefix("epubcfi("), let fraction = value["fraction"] as? Double {
            do {
                try store.update(account: source.account, itemID: source.itemID, format: "epub", location: location, fraction: fraction, rotation: 0, fileID: source.fileID)
                store.sync(api: api)
                savingError = nil
            } catch { self.savingError = "Reading could not be saved: " + error.localizedDescription }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(["file", "blob", "about"].contains(scheme ?? "") ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; error = "The reader stopped. Close and reopen the book to restore your passage." }
    @objc func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard ready else { return }
        call("turn", gesture.direction == .left)
    }
    func call<T: Encodable>(_ name: String, _ argument: T) {
        guard let data = try? JSONEncoder().encode(argument), let json = String(data: data, encoding: .utf8) else { return }
        web?.evaluateJavaScript(name + "(" + json + "); null;") { [weak self] _, error in
            if let error { self?.error = "The reader could not continue: " + error.localizedDescription }
        }
    }
    private enum ReaderFailure: LocalizedError {
        case invalid
        var errorDescription: String? { "This EPUB is damaged or not a supported EPUB archive." }
    }
}

private struct EPUBCanvas: UIViewRepresentable {
    let reading: EPUBReading
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(reading, name: "reader")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.accessibilityIdentifier = "epub-document"
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let gesture = UISwipeGestureRecognizer(target: reading, action: #selector(EPUBReading.swiped(_:)))
            gesture.direction = direction
            gesture.cancelsTouchesInView = false
            web.addGestureRecognizer(gesture)
        }
        reading.attach(web)
        return web
    }
    func makeCoordinator() -> EPUBReading { reading }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: EPUBReading) { coordinator.detach() }
}

struct EPUBReader: View {
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.presentationMode) private var presentation
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var reading: EPUBReading
    @ObservedObject private var store: ReadingStore
    @State private var contents = false
    @State private var settings = false
    init(source: ReadingSource, api: APIClient, store: ReadingStore) {
        self.store = store
        _reading = StateObject(wrappedValue: EPUBReading(source: source, api: api, store: store))
    }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    EPUBCanvas(reading: reading)
                    if let error = reading.error { RecoveryCard(message: error) { reading.open() }.padding().background(ShelfStyle.background) }
                    else if !reading.ready { ProgressView("Opening EPUB…").padding().background(ShelfStyle.background) }
                }
                HStack {
                    Button { reading.call("turn", false) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous page")
                    Spacer()
                    Button { contents = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Contents")
                    Button { settings = true } label: { Image(systemName: "textformat.size") }.accessibilityLabel("Reading settings")
                    Spacer()
                    Button { reading.call("turn", true) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next page")
                }.padding().disabled(!reading.ready)
                if player.session != nil {
                    HStack {
                        Text(player.title).font(.caption).lineLimit(1)
                        Text(String(Int(player.currentTime))).font(.caption.monospacedDigit()).accessibilityIdentifier("reader-audio-elapsed")
                        Spacer()
                        playbackToggle(player, prefix: "reader-")
                        Button("Stop listening") { Task { do { try await player.stop() } catch { player.error = ConnectionStore.recovery(for: error) } } }
                    }.padding()
                }
                if let error = store.error ?? reading.savingError {
                    Text(error).font(.caption).foregroundColor(.red).padding(.horizontal).accessibilityIdentifier("reading-save-error")
                } else if store.waitingForListening {
                    Text("Passage saved on this device. Sync follows when listening closes.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                }
            }.navigationTitle(reading.source.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close reader") { presentation.wrappedValue.dismiss() } } }
                .sheet(isPresented: $contents) {
                    NavigationView { List(reading.chapters) { chapter in Button(chapter.title) { reading.call("navigate", chapter.href); contents = false } }.navigationTitle("Contents").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { contents = false } } } }.navigationViewStyle(StackNavigationViewStyle())
                }
                .sheet(isPresented: $settings) {
                    NavigationView {
                        Form {
                            Picker("Volume buttons", selection: $reading.preferences.volume) {
                                Text("Enabled").tag("enabled"); Text("Mirrored").tag("mirrored"); Text("Off").tag("none")
                            }.accessibilityIdentifier("reader-volume-mode")
                            HStack {
                                Text("While listening")
                                Spacer()
                                Toggle("Volume navigation while listening", isOn: $reading.preferences.volumeWhileListening).labelsHidden().accessibilityLabel("Volume navigation while listening").fixedSize()
                            }
                            HStack {
                                Text("Keep screen awake")
                                Spacer()
                                Toggle("Keep screen awake", isOn: $reading.preferences.keepAwake).labelsHidden().accessibilityLabel("Keep screen awake").fixedSize()
                            }
                            Picker("Theme", selection: $reading.preferences.theme) { Text("Light").tag("light"); Text("Dark").tag("dark"); Text("Black").tag("black") }
                            Picker("Font", selection: $reading.preferences.font) { Text("Serif").tag("serif"); Text("Sans serif").tag("sans-serif"); Text("Monospace").tag("monospace") }
                            Text("Font size \(Int(reading.preferences.scale))%")
                            Slider(value: $reading.preferences.scale, in: 5...300, step: 5).accessibilityLabel("Font size")
                            Text("Line spacing \(Int(reading.preferences.spacing))%")
                            Slider(value: $reading.preferences.spacing, in: 100...300, step: 5).accessibilityLabel("Line spacing")
                            Text("Text weight \(Int(reading.preferences.stroke))")
                            Slider(value: $reading.preferences.stroke, in: 0...300, step: 5).accessibilityLabel("Text weight")
                            Picker("Spread", selection: $reading.preferences.spread) { Text("Automatic").tag("auto"); Text("Single page").tag("none"); Text("Two pages").tag("always") }
                        }.navigationTitle("Reading settings").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { settings = false } } }
                    }.navigationViewStyle(StackNavigationViewStyle())
                }
        }.navigationViewStyle(StackNavigationViewStyle()).accentColor(ShelfStyle.accent)
            .onAppear { reading.context(listening: player.session != nil || player.preparing, active: scenePhase == .active && !contents && !settings) }
            .onChange(of: player.session?.id) { _ in reading.context(listening: player.session != nil || player.preparing, active: scenePhase == .active && !contents && !settings) }
            .onChange(of: player.preparing) { _ in reading.context(listening: player.session != nil || player.preparing, active: scenePhase == .active && !contents && !settings) }
            .onChange(of: scenePhase) { phase in reading.context(listening: player.session != nil || player.preparing, active: phase == .active && !contents && !settings) }
            .onChange(of: contents) { _ in reading.context(listening: player.session != nil || player.preparing, active: scenePhase == .active && !contents && !settings) }
            .onChange(of: settings) { _ in reading.context(listening: player.session != nil || player.preparing, active: scenePhase == .active && !contents && !settings) }
            .onDisappear { reading.detach() }
    }
}

struct EbookReader: View {
    let source: ReadingSource
    let api: APIClient
    let store: ReadingStore
    var body: some View {
        if source.ebook.format == "pdf" { PDFReader(source: source, api: api, store: store) }
        else { EPUBReader(source: source, api: api, store: store) }
    }
}
