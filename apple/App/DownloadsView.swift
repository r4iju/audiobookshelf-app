import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        NavigationView {
            ShelfList {
                NavigationLink(l10n("Network preferences"), destination: NativeNetworkSettings())
                if let error = downloads.error { Text(error).foregroundColor(.red) }
                if downloads.visible.isEmpty { Text(l10n("Save books or episodes from your library to listen offline.")).foregroundColor(.secondary) }
                ForEach(downloads.visible) { entry in
                    if entry.state == .ready {
                        NavigationLink(destination: OfflineDetails(entry: entry)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.media.title).font(.headline)
                                Label(l10n("Available offline"), systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.secondary)
                            }
                        }.accessibilityIdentifier("offline-" + entry.media.libraryItemID + (entry.supplementaryID.map { "-" + $0 } ?? ""))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.media.title).font(.headline)
                            Text(entry.error ?? l10n(entry.state.rawValue.capitalized)).font(.caption).foregroundColor(.secondary)
                            if entry.state == .queued {
                                Text(l10n("{0} of {1} files saved", entry.finished.count, entry.parts.count)).font(.caption)
                                ProgressView(value: downloads.fraction(for: entry))
                                Button(l10n("Cancel download")) { NativeHaptic.impact("download"); downloads.cancel(entry) }
                            } else { Button(l10n("Retry download")) { NativeHaptic.impact("download"); Task { await downloads.retry(entry) } } }
                            Button(l10n("Remove download")) { NativeHaptic.impact("delete-local"); Task { await downloads.remove(entry, player: player) } }
                        }.padding(.vertical, 8)
                    }
                }
            }.buttonStyle(BorderlessButtonStyle()).navigationTitle(l10n("Downloads"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { downloads.presented = false } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear { downloads.refresh() }.nativeLocalization()
    }
}

private struct OfflineDetails: View {
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var readingStore: ReadingStore
    @State private var reader: ReadingSource?
    @Environment(\.presentationMode) private var presentation
    let entry: NativeDownloads.Entry
    @State private var error: String?
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "books.vertical.fill").font(.system(size: 64)).foregroundColor(ShelfStyle.accent)
                Text(entry.media.title).font(.system(.largeTitle, design: .serif).bold())
                Text(entry.media.author).foregroundColor(.secondary)
                Label(l10n("Available offline"), systemImage: "checkmark.circle.fill")
                if let ebook = entry.ebook, ["pdf", "epub"].contains(ebook.format) {
                    Button(l10n("Read {0}", ebook.format.uppercased())) {
                        do { reader = ReadingSource(account: entry.account, itemID: entry.media.libraryItemID, title: entry.media.title, ebook: ebook, file: try downloads.ebookURL(entry), progress: entry.readingProgress, fileID: entry.supplementaryID) }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("read-downloaded-ebook")
                }
                if !entry.tracks.isEmpty { Button(l10n("Play offline")) {
                    NativeHaptic.impact("play")
                    do {
                        let audio = try downloads.audio(entry)
                        Task { await player.startOffline(audio); if player.offlineID == entry.id { downloads.presented = false } }
                    } catch { self.error = error.localizedDescription }
                }.font(.headline) }
                ForEach(entry.chapters) { chapter in Text(chapter.title) }
                if let error { Text(error).foregroundColor(.red) }
                Button(l10n("Remove download")) { NativeHaptic.impact("delete-local"); Task { await downloads.remove(entry, player: player); presentation.wrappedValue.dismiss() } }.foregroundColor(.red)
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(appearance.background).navigationTitle(entry.media.title).navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $reader) { source in EbookReader(source: source, api: downloads.api, store: readingStore) }
    }
}
