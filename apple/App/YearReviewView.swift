import SwiftUI
import UIKit

@MainActor private final class YearReviewStore: ObservableObject {
    @Published private(set) var stats: YearListeningStats?
    /// Export snapshots for the loaded year and account; replaced (never mutated) when covers arrive.
    @Published private(set) var export: YearExportSnapshot?
    /// Present only for admin and root accounts whose server granted `api/stats/year`.
    @Published private(set) var serverExport: YearExportServerSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var year = Calendar(identifier: .gregorian).component(.year, from: Date())
    private let api: APIClient
    private var revision = UUID()
    private var extras: Task<Void, Never>?
    init(api: APIClient) { self.api = api }
    func load(year: Int) async {
        let request = UUID(); revision = request
        extras?.cancel(); extras = nil
        self.year = year; stats = nil; export = nil; serverExport = nil; error = nil; loading = true
        defer { if revision == request { loading = false } }
        do {
            // The authorization revision changes on every sign-in, so it also catches A -> B -> A switches.
            let authorization = api.authorizationRevision
            let owner = try await api.currentAccount()
            let value = try await api.yearListeningStats(year)
            guard revision == request, api.authorizationRevision == authorization, try await api.currentAccount() == owner else { return }
            stats = value
            export = YearExportSnapshot(stats: value, year: year)
            extras = Task { [weak self] in await self?.loadExports(year: year, stats: value, authorization: authorization, request: request) }
        } catch { if revision == request { self.error = ConnectionStore.recovery(for: error) } }
    }
    func invalidate() { revision = UUID(); extras?.cancel(); extras = nil; stats = nil; export = nil; serverExport = nil; loading = false }

    /// Covers and the admin server year are optional: any failure, including a 403 or a missing
    /// cover, leaves the export without them. Every step is scoped to the request and to the
    /// authorization revision the stats were loaded under; any sign-in change ends the sequence.
    private func loadExports(year: Int, stats: YearListeningStats, authorization: UUID, request: UUID) async {
        func valid() -> Bool { revision == request && api.authorizationRevision == authorization && !Task.isCancelled }
        if let art = try? await YearExportArtworkLoader.load(
            year: year, primary: stats.finishedBooksWithCovers, secondary: stats.booksWithCovers,
            api: api, authorization: authorization), valid() {
            export = YearExportSnapshot(stats: stats, year: year, artwork: art)
        }
        guard valid(), let user = try? await api.me(), valid(), user.canViewServerYearStats,
              let server = try? await api.serverYearStats(year), valid() else { return }
        serverExport = YearExportServerSnapshot(stats: server, year: year, artwork: nil)
        if let art = try? await YearExportArtworkLoader.load(
            year: year, primary: [], secondary: server.booksAddedWithCovers,
            api: api, authorization: authorization), valid() {
            serverExport = YearExportServerSnapshot(stats: server, year: year, artwork: art)
        }
    }
}

/// The snapshot captured when a share is tapped; later loads never change an open composer.
private enum YearReviewExport: Identifiable {
    case listener(YearExportSnapshot)
    case server(YearExportServerSnapshot)
    var id: UUID {
        switch self {
        case .listener(let snapshot): return snapshot.id
        case .server(let snapshot): return snapshot.id
        }
    }
}

struct YearReviewView: View {
    @StateObject private var store: YearReviewStore
    @State private var exporting: YearReviewExport?
    init(api: APIClient) { _store = StateObject(wrappedValue: YearReviewStore(api: api)) }
    private func minutes(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: max(value, 0) / 60)) ?? "0"
    }
    private func month(_ value: Int) -> String {
        guard (0..<12).contains(value) else { return "Unknown month" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        return formatter.monthSymbols[value]
    }
    var body: some View {
        ShelfList {
            HStack {
                Button { Task { await store.load(year: store.year - 1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous year").disabled(store.year <= 2000)
                Spacer()
                Text(String(store.year)).font(.title2.monospacedDigit().weight(.bold))
                Spacer()
                Button { Task { await store.load(year: store.year + 1) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next year").disabled(store.year >= Calendar(identifier: .gregorian).component(.year, from: Date()))
            }
            if store.loading { ProgressView("Opening your year…") }
            if let error = store.error { RecoveryCard(message: error) { Task { await store.load(year: store.year) } } }
            if let stats = store.stats {
                Section(header: Text("Your year of listening")) {
                    Text("\(minutes(stats.totalListeningTime)) minutes listened").font(.title2.bold())
                    Text("\(stats.numBooksFinished) books finished")
                    Text("\(stats.numBooksListened) books listened to")
                    Text("\(stats.totalListeningSessions) listening sessions")
                    Label("\(minutes(stats.totalBookListeningTime)) audiobook minutes", systemImage: "book")
                    Label("\(minutes(stats.totalPodcastListeningTime)) podcast minutes", systemImage: "mic")
                }
                if !stats.topAuthors.isEmpty {
                    Section(header: Text("Top authors")) {
                        ForEach(stats.topAuthors.indices, id: \.self) { index in
                            ranked(stats.topAuthors[index].name, time: stats.topAuthors[index].time)
                        }
                    }
                }
                if let narrator = stats.mostListenedNarrator {
                    Section(header: Text("Top narrator")) { ranked(narrator.name, time: narrator.time) }
                }
                if !stats.topGenres.isEmpty {
                    Section(header: Text("Top genres")) {
                        ForEach(stats.topGenres.indices, id: \.self) { index in
                            ranked(stats.topGenres[index].genre, time: stats.topGenres[index].time)
                        }
                    }
                }
                if let topMonth = stats.mostListenedMonth {
                    Section(header: Text("Most listened month")) { ranked(month(topMonth.month), time: topMonth.time) }
                }
                if let book = stats.longestAudiobookFinished {
                    Section(header: Text("Longest audiobook finished")) { ranked(book.title, time: book.duration) }
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle("Year in review")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { shareButton } }
            .sheet(item: $exporting) { export in
                switch export {
                case .listener(let snapshot): YearExportSheet(snapshot: snapshot) { exporting = nil }
                case .server(let snapshot): YearExportSheet(server: snapshot) { exporting = nil }
                }
            }
            .onAppear { Task { await store.load(year: store.year) } }
            .onDisappear { store.invalidate() }
    }
    @ViewBuilder private var shareButton: some View {
        if let server = store.serverExport {
            Menu {
                Button { exporting = store.export.map(YearReviewExport.listener) } label: { Label("Share My Year", systemImage: "person") }
                    .disabled(store.export == nil)
                Button { exporting = .server(server) } label: { Label("Share Server Year", systemImage: "server.rack") }
            } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share year in review")
        } else {
            Button { exporting = store.export.map(YearReviewExport.listener) } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share year in review").disabled(store.export == nil)
        }
    }
    private func ranked(_ name: String, time: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Text("\(minutes(time)) minutes").font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }
}
