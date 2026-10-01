import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    var body: some View {
        NavigationView {
            List {
                Toggle("Download over cellular", isOn: $downloads.cellular)
                if let error = downloads.error { Text(error).foregroundColor(.red) }
                if downloads.visible.isEmpty { Text("Save books or episodes from your library to listen offline.").foregroundColor(.secondary) }
                ForEach(downloads.visible) { entry in
                    if entry.state == .ready {
                        NavigationLink(destination: OfflineDetails(entry: entry)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.media.title).font(.headline)
                                Label("Available offline", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.secondary)
                            }
                        }.accessibilityIdentifier("offline-" + entry.media.libraryItemID)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.media.title).font(.headline)
                            Text(entry.error ?? entry.state.rawValue.capitalized).font(.caption).foregroundColor(.secondary)
                            if entry.state == .queued {
                                Text("\(entry.finished.count) of \(entry.tracks.count) files saved").font(.caption)
                                ProgressView(value: downloads.fraction(for: entry))
                                Button("Cancel download") { downloads.cancel(entry) }
                            } else { Button("Retry download") { downloads.retry(entry) } }
                            Button("Remove download") { Task { await downloads.remove(entry, player: player) } }
                        }.padding(.vertical, 8)
                    }
                }
            }.buttonStyle(BorderlessButtonStyle()).navigationTitle("Downloads")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { downloads.presented = false } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear { downloads.refresh() }
    }
}

private struct OfflineDetails: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.presentationMode) private var presentation
    let entry: NativeDownloads.Entry
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "books.vertical.fill").font(.system(size: 64)).foregroundColor(ShelfStyle.accent)
                Text(entry.media.title).font(.system(.largeTitle, design: .serif).bold())
                Text(entry.media.author).foregroundColor(.secondary)
                Label("Available offline", systemImage: "checkmark.circle.fill")
                Button("Play offline") {
                    do {
                        let audio = try downloads.audio(entry)
                        Task { await player.startOffline(audio); if player.offlineID == entry.id { downloads.presented = false } }
                    } catch { self.error = error.localizedDescription }
                }.font(.headline)
                ForEach(entry.chapters) { chapter in Text(chapter.title) }
                if let error { Text(error).foregroundColor(.red) }
                Button("Remove download") { Task { await downloads.remove(entry, player: player); presentation.wrappedValue.dismiss() } }.foregroundColor(.red)
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(ShelfStyle.background).navigationTitle(entry.media.title).navigationBarTitleDisplayMode(.inline)
    }
}
