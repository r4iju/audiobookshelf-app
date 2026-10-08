import SwiftUI

struct DownloadsView: View {
    var embedded = false
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        NativeNavigation {
            ShelfList {
                Section {
                    NavigationLink(l10n("Network preferences"), destination: NativeNetworkSettings())
                    if let error = downloads.error { Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.red) }
                }
                if downloads.visible.isEmpty {
                    CatalogStatus(title: l10n("No downloads yet"), message: l10n("Save books or episodes from your library to listen offline."), symbol: "arrow.down.circle")
                }
                if !downloads.visible.isEmpty {
                Section(header: Text(l10n("Saved on this device"))) {
                ForEach(downloads.visible) { entry in
                    if entry.state == .ready {
                        NavigationLink(destination: OfflineDetails(entry: entry)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.media.title).font(.headline)
                                Label(l10n("Available offline"), systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(ShelfStyle.secondaryText)
                            }
                        }.accessibilityIdentifier("offline-" + entry.media.libraryItemID + (entry.supplementaryID.map { "-" + $0 } ?? ""))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.media.title).font(.headline)
                            Label(entry.error ?? l10n(entry.state.rawValue.capitalized), systemImage: entry.state == .queued ? "arrow.down.circle" : "exclamationmark.triangle").font(.callout).foregroundColor(ShelfStyle.secondaryText)
                            if entry.state == .queued {
                                Text(l10n("{0} of {1} files saved", entry.finished.count, entry.parts.count)).font(.caption)
                                ProgressView(value: downloads.fraction(for: entry))
                            }
                            VStack(alignment: .leading, spacing: 12) {
                            if entry.state == .queued {
                                Button(l10n("Cancel download")) { NativeHaptic.impact("download"); downloads.cancel(entry) }
                            } else { Button(l10n("Retry download")) { NativeHaptic.impact("download"); Task { await downloads.retry(entry) } } }
                            if entry.audioAvailable { NavigationLink(l10n("Play offline"), destination: OfflineDetails(entry: entry)).accessibilityIdentifier("offline-audio-" + entry.media.libraryItemID) }
                            Button(l10n("Remove download")) { NativeHaptic.impact("delete-local"); Task { await downloads.remove(entry, player: player) } }.foregroundColor(.red)
                            }.buttonStyle(BorderlessButtonStyle())
                        }.padding(.vertical, 8)
                    }
                }
                }
                }
            }.listStyle(InsetGroupedListStyle()).buttonStyle(BorderlessButtonStyle()).navigationTitle(l10n("Downloads"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { if !embedded { Button(l10n("Done")) { downloads.presented = false } } } }
        }.onAppear { downloads.refresh() }.nativeLocalization()
    }
}

private struct OfflineDetails: View {
    @EnvironmentObject private var downloads: NativeDownloads
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var readingStore: ReadingStore
    @State private var reader: ReadingSource?
    @Environment(\.presentationMode) private var presentation
    let entry: NativeDownloads.Entry
    @State private var error: String?
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfList {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "books.vertical.fill").font(.largeTitle).foregroundColor(ShelfStyle.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.media.title).font(.title2.bold())
                        Text(entry.media.author).font(.subheadline).foregroundColor(ShelfStyle.secondaryText)
                        Label(l10n("Available offline"), systemImage: "checkmark.circle.fill").font(.callout)
                    }
                }.padding(.vertical, 8)
            }
            Section(header: Text(l10n("Available media"))) {
                if let ebook = entry.ebook, entry.ebookAvailable, ["pdf", "epub"].contains(ebook.format) {
                    Button(l10n("Read {0}", ebook.format.uppercased())) {
                        do { reader = ReadingSource(account: entry.account, itemID: entry.media.libraryItemID, title: entry.media.title, ebook: ebook, file: try downloads.ebookURL(entry), progress: entry.readingProgress, fileID: entry.supplementaryID, progressGeneration: entry.media.progressGeneration) }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("read-downloaded-ebook").buttonStyle(BorderlessButtonStyle())
                }
                if !entry.tracks.isEmpty {
                    Button(l10n("Play offline")) {
                        NativeHaptic.impact("play")
                        do {
                            let audio = try downloads.audio(entry)
                            Task { await player.startOffline(audio); if player.offlineID == entry.id { downloads.presented = false } }
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(BorderlessButtonStyle())
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.red) }
            }
            if !entry.chapters.isEmpty {
                Section(header: Text(l10n("Chapters"))) {
                    ForEach(entry.chapters) { chapter in Text(chapter.title).padding(.vertical, 4) }
                }
            }
            Section {
                Button(l10n("Remove download")) { NativeHaptic.impact("delete-local"); Task { await downloads.remove(entry, player: player); presentation.wrappedValue.dismiss() } }
                    .foregroundColor(.red).buttonStyle(BorderlessButtonStyle())
            }
        }.navigationTitle(entry.media.title).navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $reader) { source in EbookReader(source: source, api: downloads.api, store: readingStore) }
    }
}
