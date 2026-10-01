import SwiftUI
import UIKit

struct PlaybackContainer<Content: View>: View {
    @EnvironmentObject private var player: ApplePlayback
    @State private var expanded = false
    let content: Content
    var body: some View {
        content.padding(.bottom, player.session == nil && !player.preparing ? 0 : 86)
            .overlay(miniPlayer, alignment: .bottom)
            .fullScreenCover(isPresented: $expanded) { NowListening().environmentObject(player) }
    }
    private var miniPlayer: some View {
        Group {
                if player.session != nil || player.preparing {
                    HStack(spacing: 14) {
                        Button { expanded = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "headphones").font(.title2).foregroundColor(ShelfStyle.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(player.title).font(.headline).lineLimit(1)
                                    Text(player.preparing || player.seeking ? "Preparing audio…" : ShelfTime.describe(player.currentTime) + " of " + ShelfTime.describe(player.session?.duration ?? 0))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("mini-player")
                        playbackToggle(player)
                    }.padding(18).background(ShelfStyle.card).cornerRadius(20).shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                        .padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: 900)
                }
        }
    }
}

struct NowListening: View {
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.presentationMode) private var presentation
    @State private var scrubbing = false
    @State private var position: Double = 0
    @State private var panel: ListeningPanel?
    @State private var artwork: UIImage?
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32).fill(ShelfStyle.accent.opacity(0.12))
                        if let artwork { Image(uiImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "books.vertical.fill").font(.system(size: 90)).foregroundColor(ShelfStyle.accent) }
                    }.frame(width: 220, height: 260).clipped().cornerRadius(24).padding(.top, 20).accessibilityHidden(true)
                    VStack(spacing: 10) {
                        if let chapter = player.currentChapter {
                            Text(chapter.title).font(.headline)
                            Text(ShelfTime.describe(player.currentTime - chapter.start) + " of " + ShelfTime.describe(chapter.end - chapter.start))
                                .font(.caption).foregroundColor(.secondary).accessibilityIdentifier("chapter-elapsed")
                        }
                        Text(player.title).font(.system(.title, design: .serif).bold()).multilineTextAlignment(.center)
                        Text(player.author).foregroundColor(.secondary)
                        if let session = player.session {
                            Text("File \(player.trackIndex + 1) of \(session.audioTracks.count)").font(.caption).foregroundColor(.secondary)
                        }
                        Text(player.preparing ? "Preparing audio…" : player.seeking ? "Seeking…" : player.playing ? "Playing" : "Paused")
                            .font(.caption).foregroundColor(.secondary).accessibilityIdentifier("playback-status")
                    }
                    VStack(spacing: 10) {
                        Slider(value: Binding(get: { scrubbing ? position : player.currentTime }, set: { position = $0 }), in: 0...max(player.session?.duration ?? 0, 1), onEditingChanged: { editing in
                            scrubbing = editing
                            if !editing { Task { do { try await player.seek(to: position, autoplay: player.wantsPlayback) } catch { player.error = ConnectionStore.recovery(for: error) } } }
                        }).accentColor(ShelfStyle.accent).accessibilityIdentifier("playback-position")
                        HStack {
                            Text(ShelfTime.describe(scrubbing ? position : player.currentTime)).accessibilityIdentifier("playback-elapsed")
                            Spacer()
                            Text("−" + ShelfTime.describe(max((player.session?.duration ?? 0) - player.currentTime, 0)))
                        }.font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    }
                    HStack(spacing: 38) {
                        Button { Task { await player.skip(-Double(player.backwardInterval)) } } label: { VStack { Image(systemName: "gobackward").font(.largeTitle); Text("\(player.backwardInterval)").font(.caption) } }.accessibilityLabel("Back \(player.backwardInterval) seconds")
                        playbackToggle(player, large: true)
                        Button { Task { await player.skip(Double(player.forwardInterval)) } } label: { VStack { Image(systemName: "goforward").font(.largeTitle); Text("\(player.forwardInterval)").font(.caption) } }.accessibilityLabel("Forward \(player.forwardInterval) seconds")
                    }.foregroundColor(ShelfStyle.accent)
                    HStack(spacing: 24) {
                        Button { panel = .chapters } label: { Label("Chapters", systemImage: "list.bullet") }.disabled(player.session?.chapters?.isEmpty != false)
                        Button { panel = .speed } label: { VStack { Image(systemName: "speedometer"); Text(String(format: "%g×", player.speed)) } }.accessibilityLabel("Playback speed")
                        Button { panel = .bookmarks } label: { Label("Bookmarks", systemImage: "bookmark") }.disabled(!player.bookmarkSupported)
                        Button { panel = .sleep } label: { Label("Sleep timer", systemImage: "moon") }.disabled(player.session == nil)
                    }.labelStyle(ListeningControlLabelStyle()).font(.caption).foregroundColor(ShelfStyle.accent)
                    if let remaining = player.sleepRemaining { Text("Sleep in " + ShelfTime.describe(remaining)).font(.caption).foregroundColor(.secondary) }
                    if player.sleepChapterEnd != nil { Text("Sleep at chapter end").font(.caption).foregroundColor(.secondary) }
                    Button { panel = .settings } label: { Label("Playback settings", systemImage: "slider.horizontal.3") }.font(.footnote)
                    if let error = player.error { Text(error).font(.callout).foregroundColor(.red).accessibilityIdentifier("playback-error") }
                    Button("Close playback") {
                        Task {
                            do { try await player.stop(); presentation.wrappedValue.dismiss() }
                            catch { player.error = ConnectionStore.recovery(for: error) }
                        }
                    }.font(.footnote).foregroundColor(.secondary)
                }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(ShelfStyle.background).navigationTitle("Now listening").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle())
            .sheet(item: $panel) { _ in ListeningControls(panel: $panel).environmentObject(player) }
            .onAppear { loadArtwork() }
            .onChange(of: player.itemID) { _ in loadArtwork() }
    }
    private func loadArtwork() {
        artwork = nil
        guard let id = player.itemID else { return }
        Task {
            guard let data = try? await connection.api.coverData(itemID: id), player.itemID == id else { return }
            artwork = UIImage(data: data)
        }
    }
}

enum ListeningPanel: String, Identifiable { case chapters, speed, bookmarks, sleep, settings; var id: String { rawValue } }

private struct ListeningControlLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { VStack(spacing: 8) { configuration.icon.font(.title2); configuration.title } }
}

struct ListeningControls: View {
    @EnvironmentObject private var player: ApplePlayback
    @Binding var panel: ListeningPanel?
    @State private var bookmarkTitle = ""
    @State private var editing: Bookmark?
    @State private var seconds = ""
    var body: some View {
        NavigationView {
            Form {
                switch panel {
                case .chapters:
                    ForEach(player.session?.chapters ?? []) { chapter in
                        Button {
                            Task { await player.skip(chapter.start - player.currentTime) }
                            panel = nil
                        } label: {
                            HStack { Text(chapter.title); Spacer(); Text(ShelfTime.describe(chapter.start)).foregroundColor(.secondary) }
                        }.accessibilityIdentifier("chapter-\(chapter.id)")
                    }
                case .speed:
                    ForEach([0.5, 1, 1.2, 1.5, 1.7, 2, 3], id: \.self) { rate in
                        Button(String(format: "%g×", rate)) { player.speed = Float(rate); player.changeSpeed(); panel = nil }
                            .accessibilityIdentifier(String(format: "speed-%g", rate))
                    }
                    Stepper(value: Binding(get: { Double(player.speed) }, set: { player.speed = Float($0); player.changeSpeed() }), in: 0.5...10, step: 0.1) {
                        Text(String(format: "Custom speed: %.1f×", player.speed))
                    }
                case .bookmarks:
                    Section(header: Text(editing == nil ? "Add a bookmark here" : "Edit bookmark")) {
                        TextField("Note", text: $bookmarkTitle).accessibilityIdentifier("bookmark-title")
                        Button("Save bookmark") {
                            Task {
                                await player.saveBookmark(title: bookmarkTitle, editing: editing)
                                if player.bookmarkError == nil { bookmarkTitle = ""; editing = nil }
                            }
                        }.disabled(bookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || player.bookmarkBusy)
                    }
                    if let error = player.bookmarkError {
                        Text(error).foregroundColor(.red)
                        Button("Retry bookmarks") { Task { await player.loadBookmarks() } }
                    }
                    if player.bookmarks.isEmpty { Text("No bookmarks yet").foregroundColor(.secondary) }
                    ForEach(player.bookmarks) { bookmark in
                        VStack(alignment: .leading, spacing: 12) {
                            Button(bookmark.title) { Task { await player.skip(bookmark.time - player.currentTime) }; panel = nil }
                            Text(ShelfTime.describe(bookmark.time)).font(.caption).foregroundColor(.secondary)
                            HStack {
                                Button("Edit") { editing = bookmark; bookmarkTitle = bookmark.title }.accessibilityLabel("Edit " + bookmark.title)
                                Spacer()
                                Button("Delete") { Task { await player.deleteBookmark(bookmark) } }.foregroundColor(.red).accessibilityLabel("Delete " + bookmark.title)
                            }.font(.caption)
                        }.buttonStyle(BorderlessButtonStyle()).disabled(player.bookmarkBusy)
                    }
                case .sleep:
                    if player.sleepRemaining != nil || player.sleepChapterEnd != nil {
                        Section(header: Text("Active timer")) {
                            if let remaining = player.sleepRemaining {
                                Text("Sleep in " + ShelfTime.describe(remaining))
                                Button("Add 5 minutes") { player.adjustSleepTimer(by: 300) }
                                Button("Subtract 5 minutes") { player.adjustSleepTimer(by: -300) }
                            } else { Text("Sleep at chapter end") }
                            Button("Reset timer") { player.resetSleepTimer(); panel = nil }
                            Button("Cancel timer") { player.cancelSleepTimer(); panel = nil }
                        }
                    }
                    Toggle("Fade audio in the last minute", isOn: $player.fadeSleepTimer)
                    if player.sleepRemaining != nil { Text("Audio volume: \(Int(player.audioVolume * 100))%").accessibilityIdentifier("fade-volume") }
                    Section(header: Text("Sleep after listening")) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                            Button("\(minutes) minutes") { player.setSleepTimer(seconds: Double(minutes * 60)); panel = nil }
                        }
                        TextField("Custom duration in seconds", text: $seconds).keyboardType(.numberPad).accessibilityIdentifier("timer-seconds")
                        Button("Start timer") { if let duration = Double(seconds) { player.setSleepTimer(seconds: duration); panel = nil } }
                            .disabled((Double(seconds) ?? 0) <= 0)
                        Button("End of chapter") { player.setChapterSleepTimer(); panel = nil }.disabled(player.currentChapter == nil)
                    }
                case .settings:
                    Toggle("Rewind after a pause", isOn: $player.rewindAfterPause)
                    Toggle("Allow seeking from system media controls", isOn: $player.allowMediaSeeking)
                    Picker("Forward interval", selection: $player.forwardInterval) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in Text("\(seconds) seconds").tag(seconds) }
                    }.pickerStyle(MenuPickerStyle()).accessibilityIdentifier("Forward interval")
                    Picker("Backward interval", selection: $player.backwardInterval) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in Text("\(seconds) seconds").tag(seconds) }
                    }.pickerStyle(MenuPickerStyle()).accessibilityIdentifier("Backward interval")
                    Toggle("Fade audio in the last minute", isOn: $player.fadeSleepTimer)
                case nil: EmptyView()
                }
            }.navigationTitle(panel?.rawValue.capitalized ?? "Listening")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { panel = nil } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear { if panel == .bookmarks { Task { await player.loadBookmarks() } } }
    }
}

@MainActor @ViewBuilder private func playbackToggle(_ player: ApplePlayback, large: Bool = false) -> some View {
    Button { player.toggle() } label: {
        Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill")
            .font(large ? .system(size: 34) : .title2)
            .frame(width: large ? 80 : 44, height: large ? 80 : 44)
            .background(large ? ShelfStyle.accent : .clear).foregroundColor(large ? .white : ShelfStyle.accent)
            .clipShape(Circle())
    }.accessibilityLabel(player.wantsPlayback ? "Pause" : "Play")
        .accessibilityIdentifier((large ? "" : "mini-") + (player.wantsPlayback ? "pause-playback" : "resume-playback"))
}
