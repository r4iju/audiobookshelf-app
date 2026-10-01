import SwiftUI

@MainActor private final class StatisticsStore: ObservableObject {
    @Published private(set) var stats: ListeningStats?
    @Published private(set) var finished = 0
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    let api: APIClient
    private var generation = UUID()
    init(api: APIClient) { self.api = api }
    func load() async {
        let request = UUID(); generation = request; loading = true; error = nil; stats = nil; finished = 0
        defer { if generation == request { loading = false } }
        do {
            let owner = try await api.currentAccount()
            async let response = api.listeningStats()
            async let currentUser = api.me()
            let (stats, user) = try await (response, currentUser)
            guard request == generation, try await api.currentAccount() == owner else { return }
            self.stats = stats
            finished = user.mediaProgress.filter { $0.isFinished == true }.count
        } catch { if request == generation { self.error = ConnectionStore.recovery(for: error) } }
    }
}

struct StatisticsView: View {
    @StateObject private var store: StatisticsStore
    init(api: APIClient) { _store = StateObject(wrappedValue: StatisticsStore(api: api)) }
    private func minutes(_ seconds: Double) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: (seconds / 60).rounded())) ?? "0"
    }
    private var recentDays: [(date: String, time: Double)] {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = formatter.string(from: date)
            return (key, store.stats?.days[key] ?? 0)
        }
    }
    var body: some View {
        List {
            if store.loading { ProgressView("Opening your statistics…") }
            if let error = store.error { RecoveryCard(message: error) { Task { await store.load() } } }
            if let stats = store.stats {
                Section(header: Text("Your listening")) {
                    Text("\(minutes(stats.totalTime)) minutes listened").font(.title2.bold())
                    Text("\(stats.days.count) days listened")
                    Text("\(store.finished) \(store.finished == 1 ? "title" : "titles") finished")
                }
                Section(header: Text("Minutes listened in the last 7 days")) {
                    ForEach(recentDays, id: \.date) { day in
                        HStack {
                            Text(day.date).font(.caption.monospacedDigit()).frame(width: 90, alignment: .leading)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 4).fill(ShelfStyle.accent)
                                    .frame(width: geometry.size.width * min(max(day.time / max(recentDays.map(\.time).max() ?? 0, 1), 0), 1))
                            }.frame(height: 10).accessibilityHidden(true)
                            Text(minutes(day.time)).font(.caption.monospacedDigit()).frame(minWidth: 32, alignment: .trailing)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("\(day.date), \(minutes(day.time)) minutes listened")
                    }
                }
                Section(header: Text("Recent sessions")) {
                    if stats.recentSessions.isEmpty { Text("No listening sessions yet.").foregroundColor(.secondary) }
                    ForEach(stats.recentSessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.mediaMetadata?.title ?? "Unavailable title").font(.headline)
                            if let author = session.mediaMetadata?.authorName, !author.isEmpty { Text(author).foregroundColor(.secondary) }
                            Text("\(minutes(session.timeListening)) minutes listened").font(.caption)
                            Text(Date(timeIntervalSince1970: session.updatedAt / 1000), style: .date).font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle("Statistics")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Refresh") { Task { await store.load() } }.disabled(store.loading) } }
            .onAppear { Task { await store.load() } }
    }
}
