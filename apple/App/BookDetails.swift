import SwiftUI

struct BookDetails: View {
    @EnvironmentObject private var player: ApplePlayback
    let item: LibraryItem
    let catalog: CatalogStore
    let progress: MediaProgress?
    @State private var expanded: LibraryItem?
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    private var book: LibraryItem { expanded ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 22) {
                    BookArtwork(item: book, catalog: catalog).frame(width: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(book.title).font(.system(.title2, design: .serif).bold())
                        Text(book.author).font(.headline).foregroundColor(.secondary)
                        if let duration = book.media.duration { Label(ShelfTime.describe(duration), systemImage: "headphones").font(.subheadline) }
                        if let narrators = book.media.metadata.narrators, !narrators.isEmpty {
                            Text("Narrated by \(narrators.joined(separator: ", "))").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                Button { Task { await player.start(item: book) } } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text((progress?.currentTime ?? 0) > 0 ? "Resume listening" : "Start listening").fontWeight(.semibold)
                        Spacer()
                    }.padding(18).foregroundColor(.white).background(ShelfStyle.accent).cornerRadius(16)
                }.disabled(player.preparing).accessibilityIdentifier("play-book")
                if let error = player.error, player.itemID == book.id { Text(error).font(.callout).foregroundColor(.red) }
                if let progress, (progress.currentTime ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress.fraction).accentColor(ShelfStyle.accent)
                        Text("\(ShelfTime.describe(progress.currentTime ?? 0)) listened · \(Int(progress.fraction * 100))% complete").font(.caption).foregroundColor(.secondary)
                    }
                }
                if let description = book.media.metadata.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About this book").font(.title3.bold())
                        Text(Self.plainDescription(description)).font(.body).lineSpacing(5).foregroundColor(.secondary)
                    }
                }
                if let chapters = book.media.chapters, !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Chapters").font(.title3.bold())
                        ForEach(chapters) { chapter in
                            HStack(alignment: .top) {
                                Text(chapter.title).font(.body)
                                Spacer()
                                Text(ShelfTime.describe(chapter.end - chapter.start)).font(.caption).foregroundColor(.secondary)
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                if let error { RecoveryCard(message: error) { load() } }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(ShelfStyle.background).navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { if expanded == nil { load() } }
            .onDisappear { request?.cancel() }
    }

    private func load() {
        request?.cancel()
        request = Task {
            do {
                let value = try await catalog.api.item(id: item.id)
                guard !Task.isCancelled else { return }
                expanded = value
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = ConnectionStore.recovery(for: error)
            }
        }
    }

    private static func plainDescription(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
