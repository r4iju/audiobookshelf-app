import SwiftUI
import PDFKit

@MainActor private final class RestoringPDFView: PDFView {
    var restorePage: PDFPage?
    var restored: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let page = restorePage else { return }
        restorePage = nil
        go(to: page)
        accessibilityValue = page.string
        restored?()
    }
}

struct ReadingSource: Identifiable {
    let id = UUID()
    let account: AccountIdentity
    let itemID: String
    let title: String
    let ebook: EbookFile
    let file: URL?
    var progress: MediaProgress? = nil
    var fileID: String? = nil
}

@MainActor private final class PDFReading: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var page = 1
    @Published private(set) var count = 0
    @Published private(set) var rotation = 0
    @Published private(set) var error: String?
    @Published var continuous = UserDefaults.standard.bool(forKey: "previewPDFContinuous") {
        didSet { UserDefaults.standard.set(continuous, forKey: "previewPDFContinuous"); configureDisplay() }
    }
    weak var view: PDFView?
    let source: ReadingSource
    let api: APIClient
    let store: ReadingStore
    private var observer: NSObjectProtocol?
    private var originalRotations: [Int] = []
    var displayedRotation: Int { document?.page(at: page - 1)?.rotation ?? rotation }
    private var restoring = false
    private var opening: Task<Void, Never>?
    private var openingID = UUID()
    init(source: ReadingSource, api: APIClient, store: ReadingStore) { self.source = source; self.api = api; self.store = store }
    func open() {
        guard document == nil, opening == nil else { return }
        let id = UUID(); openingID = id; error = nil
        opening = Task {
            await load(id: id)
            if openingID == id { opening = nil }
        }
    }
    func cancelOpen() { openingID = UUID(); opening?.cancel(); opening = nil }
    private func load(id: UUID) async {
        do {
            if source.fileID == nil {
                if let progress = source.progress { try store.adopt(progress, account: source.account, itemID: source.itemID, format: "pdf") }
                if source.file == nil { await store.reconcile(api: api, account: source.account, itemID: source.itemID, format: "pdf") }
            }
            try Task.checkCancellation()
            guard try await api.currentAccount() == source.account else { throw APIError.signInRequired }
            let data: Data
            if let file = source.file { data = try await Task.detached { try Data(contentsOf: file, options: .mappedIfSafe) }.value }
            else { data = try await api.ebookData(itemID: source.itemID, ebook: source.ebook) }
            guard !Task.isCancelled, openingID == id, try await api.currentAccount() == source.account else { throw CancellationError() }
            guard let document = PDFDocument(data: data), document.pageCount > 0, !document.isLocked else { throw ReaderFailure.invalidPDF }
            count = document.pageCount
            let saved = store.position(account: source.account, itemID: source.itemID, format: "pdf", fileID: source.fileID)
            page = min(max(Int(saved?.location ?? "1") ?? 1, 1), count)
            rotation = saved?.rotation ?? 0
            originalRotations = (0..<count).map { document.page(at: $0)?.rotation ?? 0 }
            for index in 0..<count { document.page(at: index)?.rotation = (originalRotations[index] + rotation) % 360 }
            guard openingID == id else { return }
            self.document = document
            error = nil
        } catch { if openingID == id, !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    func attach(_ view: PDFView) {
        self.view = view
        restoring = true
        view.document = document
        view.displayMode = continuous ? .singlePageContinuous : .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        if let target = document?.page(at: page - 1) { view.go(to: target); view.accessibilityValue = target.string }
        configureDisplay()
        observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changedPage() }
        }
    }
    private func configureDisplay() {
        guard let view = view as? RestoringPDFView else { return }
        restoring = true
        view.restorePage = document?.page(at: page - 1)
        view.restored = { [weak self] in self?.restoring = false }
        view.displayMode = continuous ? .singlePageContinuous : .singlePage
        view.setNeedsLayout()
    }
    func detach() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; view = nil }
    func move(_ amount: Int) {
        go(to: min(max(page + amount, 1), count))
    }
    func go(to number: Int) {
        guard number >= 1, number <= count, let target = document?.page(at: number - 1) else { return }
        view?.go(to: target); changedPage()
    }
    func rotate() {
        rotation = (rotation + 90) % 360
        for index in 0..<count { document?.page(at: index)?.rotation = (originalRotations[index] + rotation) % 360 }
        view?.layoutDocumentView(); view?.autoScales = true
        save()
    }
    private func changedPage() {
        guard !restoring, let document, let current = view?.currentPage else { return }
        page = document.index(for: current) + 1
        view?.accessibilityValue = current.string
        save()
    }
    private func save() {
        do {
            try store.update(account: source.account, itemID: source.itemID, format: "pdf", location: String(page), fraction: Double(page - 1) / Double(max(count, 1)), rotation: rotation, fileID: source.fileID)
            store.sync(api: api)
        } catch { self.error = "Reading could not be saved on this device: " + error.localizedDescription }
    }
    enum ReaderFailure: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "This PDF could not be opened. It may be damaged or require a password. Check the original file and retry." }
    }
}

private struct NativePDFCanvas: UIViewRepresentable {
    @ObservedObject var reading: PDFReading
    func makeUIView(context: Context) -> PDFView {
        let view = RestoringPDFView(); view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "pdf-document"; view.accessibilityLabel = "PDF document"
        reading.attach(view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
    static func dismantleUIView(_ view: PDFView, coordinator: ()) {}
}

struct PDFReader: View {
    @EnvironmentObject private var player: ApplePlayback
    @StateObject private var reading: PDFReading
    @State private var requestedPage = ""
    @ObservedObject private var store: ReadingStore
    @Environment(\.presentationMode) private var presentation
    init(source: ReadingSource, api: APIClient, store: ReadingStore) {
        self.store = store
        _reading = StateObject(wrappedValue: PDFReading(source: source, api: api, store: store))
    }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if reading.document != nil {
                    NativePDFCanvas(reading: reading)
                    HStack {
                        Button { reading.move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous page").disabled(reading.page <= 1)
                        Spacer()
                        Text("Page \(reading.page) of \(reading.count)").font(.callout.monospacedDigit())
                        Spacer()
                        Button { reading.move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next page").disabled(reading.page >= reading.count)
                    }.padding()
                    HStack {
                        TextField("Page", text: $requestedPage).keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 72)
                            .accessibilityIdentifier("reader-page")
                        Button("Go to page") {
                            if let page = Int(requestedPage) { reading.go(to: page) }
                            requestedPage = ""
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }.disabled(Int(requestedPage).map { $0 < 1 || $0 > reading.count } ?? true)
                        Spacer()
                    }.padding(.horizontal).padding(.bottom, 8)
                    HStack {
                        Button("Rotate page") { reading.rotate() }
                        Text("Rotation \(reading.displayedRotation)°").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("Continuous").font(.caption)
                        Toggle("Continuous", isOn: $reading.continuous).labelsHidden().accessibilityLabel("Continuous").fixedSize()
                    }.padding(.horizontal).padding(.bottom)
                    if player.session != nil {
                        HStack {
                            Text(player.title).font(.caption).lineLimit(1)
                            Text(String(Int(player.currentTime))).font(.caption.monospacedDigit()).accessibilityIdentifier("reader-audio-elapsed")
                            Spacer()
                            playbackToggle(player, prefix: "reader-")
                            Button { Task { do { try await player.stop() } catch { player.error = ConnectionStore.recovery(for: error) } } } label: { Image(systemName: "stop.circle") }
                                .accessibilityLabel("Stop listening")
                        }.padding(.horizontal).padding(.bottom, 8)
                    }
                    if let error = reading.error ?? store.error ?? player.error { Text(error).font(.caption).foregroundColor(.red).padding(.horizontal) }
                    else if store.waitingForListening { Text("Page saved on this device. Sync follows when listening closes.").font(.caption).foregroundColor(.secondary).padding(.horizontal) }
                } else if let error = reading.error { RecoveryCard(message: error) { reading.open() }.padding() }
                else { ProgressView("Opening PDF…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.background(ShelfStyle.background).navigationTitle(reading.source.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close reader") { presentation.wrappedValue.dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle())
            .onAppear { reading.open() }
            .onDisappear { reading.cancelOpen(); reading.detach() }
    }
}
