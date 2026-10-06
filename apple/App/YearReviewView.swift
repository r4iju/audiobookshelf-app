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
    func load(year: Int, copy: YearExportCopy) async {
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
            export = YearExportSnapshot(stats: value, year: year, copy: copy)
            extras = Task { [weak self] in await self?.loadExports(year: year, stats: value, authorization: authorization, request: request, copy: copy) }
        } catch { if revision == request { self.error = ConnectionStore.recovery(for: error) } }
    }
    func invalidate() { revision = UUID(); extras?.cancel(); extras = nil; stats = nil; export = nil; serverExport = nil; loading = false }

    /// Covers and the admin server year are optional: any failure, including a 403 or a missing
    /// cover, leaves the export without them. Every step is scoped to the request and to the
    /// authorization revision the stats were loaded under; any sign-in change ends the sequence.
    private func loadExports(year: Int, stats: YearListeningStats, authorization: UUID, request: UUID, copy: YearExportCopy) async {
        func valid() -> Bool { revision == request && api.authorizationRevision == authorization && !Task.isCancelled }
        if let art = try? await YearExportArtworkLoader.load(
            year: year, primary: stats.finishedBooksWithCovers, secondary: stats.booksWithCovers,
            api: api, authorization: authorization), valid() {
            export = YearExportSnapshot(stats: stats, year: year, artwork: art, copy: copy)
        }
        guard valid(), let user = try? await api.me(), valid(), user.canViewServerYearStats,
              let server = try? await api.serverYearStats(year), valid() else { return }
        serverExport = YearExportServerSnapshot(stats: server, year: year, artwork: nil, copy: copy)
        if let art = try? await YearExportArtworkLoader.load(
            year: year, primary: [], secondary: server.booksAddedWithCovers,
            api: api, authorization: authorization), valid() {
            serverExport = YearExportServerSnapshot(stats: server, year: year, artwork: art, copy: copy)
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
    @Environment(\.nativeStrings) private var l10n
    init(api: APIClient) { _store = StateObject(wrappedValue: YearReviewStore(api: api)) }
    private var exportCopy: YearExportCopy {
        YearExportCopy(translations: l10n.copy(YearExportCopy.templates), locale: l10n.language.locale)
    }
    private func minutes(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 0; formatter.locale = l10n.language.locale
        return formatter.string(from: NSNumber(value: max(value, 0) / 60)) ?? "0"
    }
    private func month(_ value: Int) -> String {
        guard (0..<12).contains(value) else { return l10n("Unknown month") }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = l10n.language.locale
        return formatter.monthSymbols[value]
    }

    var body: some View {
        ShelfList {
            HStack {
                Button { Task { await store.load(year: store.year - 1, copy: exportCopy) } } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(l10n("Previous year")).disabled(store.year <= 2000)
                Spacer()
                Text(String(store.year)).font(.title2.monospacedDigit().weight(.bold))
                Spacer()
                Button { Task { await store.load(year: store.year + 1, copy: exportCopy) } } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(l10n("Next year")).disabled(store.year >= Calendar(identifier: .gregorian).component(.year, from: Date()))
            }
            .buttonStyle(BorderlessButtonStyle())
            if store.loading { ProgressView(l10n("Opening your year…")) }
            if let error = store.error { RecoveryCard(message: error) { Task { await store.load(year: store.year, copy: exportCopy) } } }
            if let stats = store.stats {
                Section(header: Text(l10n("Your year of listening")).foregroundColor(ShelfStyle.secondaryText)) {
                    Text(l10n("{0} minutes listened", minutes(stats.totalListeningTime))).font(.title2.bold())
                    Text(l10n("{0} books finished", stats.numBooksFinished))
                    Text(l10n("{0} books listened to", stats.numBooksListened))
                    Text(l10n("{0} listening sessions", stats.totalListeningSessions))
                    Label(l10n("{0} audiobook minutes", minutes(stats.totalBookListeningTime)), systemImage: "book")
                    Label(l10n("{0} podcast minutes", minutes(stats.totalPodcastListeningTime)), systemImage: "mic")
                }
                if !stats.topAuthors.isEmpty {
                    Section(header: Text(l10n("Top authors")).foregroundColor(ShelfStyle.secondaryText)) {
                        ForEach(stats.topAuthors.indices, id: \.self) { index in
                            ranked(stats.topAuthors[index].name, time: stats.topAuthors[index].time)
                        }
                    }
                }
                if let narrator = stats.mostListenedNarrator {
                    Section(header: Text(l10n("Top narrator")).foregroundColor(ShelfStyle.secondaryText)) { ranked(narrator.name, time: narrator.time) }
                }
                if !stats.topGenres.isEmpty {
                    Section(header: Text(l10n("Top genres")).foregroundColor(ShelfStyle.secondaryText)) {
                        ForEach(stats.topGenres.indices, id: \.self) { index in
                            ranked(stats.topGenres[index].genre, time: stats.topGenres[index].time)
                        }
                    }
                }
                if let topMonth = stats.mostListenedMonth {
                    Section(header: Text(l10n("Most listened month")).foregroundColor(ShelfStyle.secondaryText)) { ranked(month(topMonth.month), time: topMonth.time) }
                }
                if let book = stats.longestAudiobookFinished {
                    Section(header: Text(l10n("Longest audiobook finished")).foregroundColor(ShelfStyle.secondaryText)) { ranked(book.title, time: book.duration) }
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Year in review")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { shareButton } }
            .sheet(item: $exporting) { export in
                switch export {
                case .listener(let snapshot): YearExportSheet(snapshot: snapshot) { exporting = nil }
                case .server(let snapshot): YearExportSheet(server: snapshot) { exporting = nil }
                }
            }

            .onAppear { Task { await store.load(year: store.year, copy: exportCopy) } }
            .onChange(of: l10n.language) { _ in Task { await store.load(year: store.year, copy: exportCopy) } }
            .onDisappear { store.invalidate() }
    }
    @ViewBuilder private var shareButton: some View {
        if let server = store.serverExport {
            Menu {
                Button { exporting = store.export.map(YearReviewExport.listener) } label: { Label(l10n("Share My Year"), systemImage: "person") }
                    .disabled(store.export == nil)
                Button { exporting = .server(server) } label: { Label(l10n("Share Server Year"), systemImage: "server.rack") }
            } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel(l10n("Share year in review"))
        } else {
            Button { exporting = store.export.map(YearReviewExport.listener) } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel(l10n("Share year in review")).disabled(store.export == nil)
        }
    }
    private func ranked(_ name: String, time: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Text(l10n("{0} minutes", minutes(time))).font(.caption).foregroundColor(ShelfStyle.secondaryText)
        }.padding(.vertical, 4)
    }
}
