import SwiftUI
import UIKit

@MainActor private final class YearReviewStore: ObservableObject {
    @Published private(set) var stats: YearListeningStats?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var year = Calendar(identifier: .gregorian).component(.year, from: Date())
    private let api: APIClient
    private var revision = UUID()
    init(api: APIClient) { self.api = api }
    func load(year: Int) async {
        let request = UUID(); revision = request
        self.year = year; stats = nil; error = nil; loading = true
        defer { if revision == request { loading = false } }
        do {
            let owner = try await api.currentAccount()
            let value = try await api.yearListeningStats(year)
            guard revision == request, try await api.currentAccount() == owner else { return }
            stats = value
        } catch { if revision == request { self.error = ConnectionStore.recovery(for: error) } }
    }
    func invalidate() { revision = UUID(); stats = nil; loading = false }
}

struct YearReviewView: View {
    @StateObject private var store: YearReviewStore
    @State private var share = false
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
    private var shareText: String {
        guard let stats = store.stats else { return "" }
        return "Audiobookshelf • \(store.year)\n\(minutes(stats.totalListeningTime)) minutes listened\n\(stats.numBooksFinished) books finished\n\(stats.numBooksListened) books listened to\n\(stats.totalListeningSessions) listening sessions"
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
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { share = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share year in review").disabled(store.stats == nil) } }
            .sheet(isPresented: $share) { YearReviewShare(text: shareText) }
            .onAppear { Task { await store.load(year: store.year) } }
            .onDisappear { store.invalidate() }
    }
    private func ranked(_ name: String, time: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Text("\(minutes(time)) minutes").font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }
}

private struct YearReviewShare: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
