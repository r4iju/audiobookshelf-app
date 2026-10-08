import SwiftUI
import UIKit

struct PlaybackContainer<Content: View>: View {
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var player: ApplePlayback
    @EnvironmentObject private var connection: ConnectionStore
    @Environment(\.nativeStrings) private var l10n
    @State private var expanded = false
    @State private var signInPrompt = false
    @State private var compactHeight: CGFloat = 96
    @State private var artwork: UIImage?
    let content: Content
    var nativeTabAccessory = false
    var body: some View {
        playbackContent
            .fullScreenCover(isPresented: $expanded) { NowListening().environmentObject(player).nativeLocalization() }
            // The full player offers the same choice next to its error.
            .onChange(of: player.needsSignIn) { needed in signInPrompt = needed && !expanded }
            .alert(isPresented: $signInPrompt) {
                Alert(title: Text(l10n("Sign in again")),
                      message: Text(l10n("The server no longer accepts this login. Listening saved on this device is kept and sent after you sign in.")),
                      primaryButton: .default(Text(l10n("Sign in"))) { connection.reauthenticate() },
                      secondaryButton: .cancel(Text(l10n("Not now"))))
            }
            .onAppear { loadArtwork() }
            .onChange(of: player.itemID) { _ in loadArtwork() }
            .onPreferenceChange(CompactPlayerHeight.self) { compactHeight = $0 }
            .recordsDiagnostics()
            .nativeLocalization()
    }
    @ViewBuilder private var playbackContent: some View {
        // 26.0 cannot disable the accessory without replacing the tab container, which loses navigation state.
        if #available(iOS 26.1, *), nativeTabAccessory {
            content.tabViewBottomAccessory(isEnabled: player.session != nil || player.preparing) { compactControls.padding(.horizontal, 12) }
        } else if #available(iOS 15, *) {
            content.safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
        } else {
            content.padding(.bottom, player.session == nil && !player.preparing ? 0 : compactHeight)
                .overlay(miniPlayer, alignment: .bottom)
        }
    }
    private var compactControls: some View {
        HStack(spacing: 14) {
            Button { expanded = true } label: {
                HStack(spacing: 14) {
                    Group {
                        if let artwork { Image(uiImage: artwork).resizable().scaledToFit() }
                        else { Image(systemName: "headphones").font(.title2).foregroundColor(ShelfStyle.accent) }
                    }.frame(width: 44, height: 44).cornerRadius(6).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.title).font(.headline).lineLimit(2)
                        Text(player.preparing || player.seeking ? l10n("Preparing audio…") : l10n("{0} of {1}", ShelfTime.describe(player.currentTime), ShelfTime.describe(player.session?.duration ?? 0)))
                            .font(.caption).foregroundColor(ShelfStyle.secondaryText)
                    }
                    Spacer()
                }
            }.buttonStyle(PlainButtonStyle()).accessibilityIdentifier("mini-player")
            playbackToggle(player, strings: l10n)
        }
    }

    private func loadArtwork() {
        artwork = nil
        guard let id = player.itemID else { return }
        Task {
            guard let data = try? await connection.api.coverData(itemID: id), player.itemID == id else { return }
            artwork = UIImage(data: data)
        }
    }

    private var miniPlayer: some View {
        Group {
                if player.session != nil || player.preparing {
                    compactControls.padding(16).nativeFloatingControl(background: appearance.card)
                        .padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: 900)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geometry in Color.clear.preference(key: CompactPlayerHeight.self, value: geometry.size.height) })
                }
        }
    }
}

struct NowListening: View {
    @Environment(\.shelfAppearance) private var appearance
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.presentationMode) private var presentation
    @Environment(\.nativeStrings) private var l10n
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var scrubbing = false
    @State private var position: Double = 0
    @State private var panel: ListeningPanel?
    @State private var artwork: UIImage?
    @AppStorage(PlayerDisplay.totalTrackKey) private var totalTrack = true
    @AppStorage(PlayerDisplay.scaleElapsedKey) private var scaleElapsed = true
    @AppStorage(PlayerDisplay.lockKey) private var locked = false
    var body: some View {
        NativeNavigation {
            GeometryReader { geometry in
                    ScrollView {
                        if geometry.size.width >= 780 && !sizeCategory.isAccessibilityCategory {
                            HStack(alignment: .center, spacing: 48) {
                                artworkContext(width: min(360, geometry.size.width * 0.35))
                                    .frame(width: min(360, geometry.size.width * 0.35))
                                listeningSurface(width: min(500, geometry.size.width - min(360, geometry.size.width * 0.35) - 128)).frame(maxWidth: 500)
                            }.padding(40).frame(maxWidth: 1100).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        } else {
                            VStack(spacing: 28) {
                                artworkContext(width: 220)
                                listeningSurface(width: min(620, geometry.size.width) - 48)
                            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                        }
                    }
                }

                .background(appearance.background).navigationTitle(l10n("Now listening")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(l10n("Done")) { presentation.wrappedValue.dismiss() } } }
        }
            .sheet(item: $panel) { _ in ListeningControls(panel: $panel).environmentObject(player).nativeLocalization().listeningSheet() }
            .onAppear { loadArtwork() }
            .onChange(of: player.itemID) { _ in loadArtwork() }
    }
    private func artworkContext(width: CGFloat) -> some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 32).fill(ShelfStyle.accent.opacity(0.12))
                if let artwork { Image(uiImage: artwork).resizable().scaledToFill() }
                else { Image(systemName: "books.vertical.fill").font(.system(size: 90)).foregroundColor(ShelfStyle.accent) }
            }.frame(width: width, height: width).clipped().cornerRadius(24).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(player.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(player.author).foregroundColor(ShelfStyle.secondaryText)
                if let chapter = player.currentChapter {
                    Text(chapter.title).font(.headline)
                    Text(l10n("{0} of {1}", ShelfTime.describe(player.currentTime - chapter.start), ShelfTime.describe(chapter.end - chapter.start)))
                        .font(.caption).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier("chapter-elapsed")
                }
                if let session = player.session {
                    Text(l10n("File {0} of {1}", player.trackIndex + 1, session.audioTracks.count)).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                }
                Text(l10n(player.preparing ? "Preparing audio…" : player.seeking ? "Seeking…" : player.playing ? "Playing" : "Paused"))
                    .font(.caption).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier("playback-status")
            }
        }
    }
    private func listeningSurface(width: CGFloat) -> some View {
        VStack(spacing: 24) {
            let display = PlayerDisplay(player: player, at: scrubbing ? position : player.currentTime, totalTrack: totalTrack, scaleElapsed: scaleElapsed)
            VStack(spacing: 10) {
                if let total = display.total {
                    ProgressView(value: total.fraction).accentColor(ShelfStyle.accent.opacity(0.6)).accessibilityHidden(true)
                    HStack {
                        Text(ShelfTime.describe(total.elapsed)).accessibilityIdentifier("total-elapsed")
                        Spacer()
                        Text("−" + ShelfTime.describe(total.remaining)).accessibilityIdentifier("total-remaining")
                    }.font(.caption2.monospacedDigit()).foregroundColor(ShelfStyle.secondaryText)
                }
                Slider(value: Binding(get: { min(max(scrubbing ? position : player.currentTime, display.range.lowerBound), display.range.upperBound) }, set: { position = $0 }), in: display.range, onEditingChanged: { editing in
                    if editing && !scrubbing { NativeHaptic.impact("scrub") }
                    scrubbing = editing
                    if !editing { Task { do { try await player.seek(to: position, autoplay: player.wantsPlayback) } catch { player.error = ConnectionStore.recovery(for: error) } } }
                }).accentColor(ShelfStyle.accent).disabled(locked).accessibilityIdentifier("playback-position")
                HStack {
                    Text(ShelfTime.describe(display.elapsed)).accessibilityIdentifier("playback-elapsed")
                    Spacer()
                    Text("−" + ShelfTime.describe(display.remaining)).accessibilityIdentifier("playback-remaining")
                }.font(.caption.monospacedDigit()).foregroundColor(ShelfStyle.secondaryText)
            }
            if locked {
                Button { NativeHaptic.impact("lock"); locked = false } label: { Label(l10n("Unlock player"), systemImage: "lock.fill") }
                    .font(.callout.bold()).foregroundColor(ShelfStyle.accent).nativeGlassButton().accessibilityIdentifier("unlock-player")
            }
            HStack(spacing: sizeCategory.isAccessibilityCategory ? 12 : 38) {
                Button { NativeHaptic.impact("skip"); Task { await player.skip(-Double(player.backwardInterval)) } } label: { VStack { Image(systemName: "gobackward").font(.system(size: 32)); Text("\(player.backwardInterval)").font(.caption) } }.frame(minWidth: 44, minHeight: 44).buttonStyle(PlainButtonStyle()).disabled(locked).accessibilityLabel(l10n("Back {0} seconds", player.backwardInterval))
                playbackToggle(player, large: true, strings: l10n)
                Button { NativeHaptic.impact("skip"); Task { await player.skip(Double(player.forwardInterval)) } } label: { VStack { Image(systemName: "goforward").font(.system(size: 32)); Text("\(player.forwardInterval)").font(.caption) } }.frame(minWidth: 44, minHeight: 44).buttonStyle(PlainButtonStyle()).disabled(locked).accessibilityLabel(l10n("Forward {0} seconds", player.forwardInterval))
            }.foregroundColor(ShelfStyle.accent)
            secondaryActions(width: width)
            if let remaining = player.sleepRemaining { Text(l10n("Sleep in {0}", ShelfTime.describe(remaining))).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
            if player.sleepChapterEnd != nil { Text(l10n("Sleep at chapter end")).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
            Button { panel = .settings } label: { Label(l10n("Playback settings"), systemImage: "slider.horizontal.3") }.font(.footnote).buttonStyle(PlainButtonStyle())
            if let error = player.error { Text(error).font(.callout).foregroundColor(.red).accessibilityIdentifier("playback-error") }
            if player.needsSignIn {
                Button(l10n("Sign in again")) {
                    presentation.wrappedValue.dismiss()
                    connection.reauthenticate()
                }.font(.callout.bold()).accessibilityIdentifier("sign-in-again")
            }
            Button(l10n("Close playback")) {
                Task {
                    do { try await player.stop(); presentation.wrappedValue.dismiss() }
                    catch { player.error = ConnectionStore.recovery(for: error) }
                }
            }.font(.footnote).foregroundColor(ShelfStyle.secondaryText).disabled(locked)
        }
    }
    @ViewBuilder private func secondaryActions(width: CGFloat) -> some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: 16) { listeningButtons }
                .labelStyle(DefaultLabelStyle())
        } else if width < 440 {
            VStack(spacing: 16) {
                toolGroup { chapterButton; speedButton }
                toolGroup { bookmarkButton; sleepButton }
            }.labelStyle(ListeningControlLabelStyle(stacked: false))
        } else if #available(iOS 15, *) {
            ControlGroup { listeningButtons }
                .controlGroupStyle(.navigation)
                .labelStyle(ListeningControlLabelStyle(stacked: true))
        } else {
            HStack(spacing: 16) { listeningButtons }
                .labelStyle(ListeningControlLabelStyle(stacked: true))
        }
    }
    @ViewBuilder private func toolGroup<Buttons: View>(@ViewBuilder content: () -> Buttons) -> some View {
        if #available(iOS 15, *) {
            ControlGroup(content: content).controlGroupStyle(.navigation)
        } else {
            HStack(spacing: 16, content: content)
        }
    }
    @ViewBuilder private var listeningButtons: some View {
        chapterButton
        speedButton
        bookmarkButton
        sleepButton
    }
    private var chapterButton: some View {
        Button { panel = .chapters } label: { Label(l10n("Chapters"), systemImage: "list.bullet").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(PlainButtonStyle()).disabled(locked || player.session?.chapters?.isEmpty != false).frame(maxWidth: .infinity).accessibilityLabel(l10n("Chapters"))
    }
    private var speedButton: some View {
        Button { panel = .speed } label: { Label(String(format: "%g×", player.speed), systemImage: "speedometer").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(PlainButtonStyle()).frame(maxWidth: .infinity).accessibilityLabel(l10n("Playback speed"))
    }
    private var bookmarkButton: some View {
        Button { panel = .bookmarks } label: { Label(l10n("Bookmarks"), systemImage: "bookmark").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(PlainButtonStyle()).disabled(locked || !player.bookmarkSupported).frame(maxWidth: .infinity).accessibilityLabel(l10n("Bookmarks"))
    }
    private var sleepButton: some View {
        Button { panel = .sleep } label: { Label(l10n("Sleep timer"), systemImage: "moon").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(PlainButtonStyle()).disabled(player.session == nil).frame(maxWidth: .infinity).accessibilityLabel(l10n("Sleep timer"))
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

/// Player track and time presentation from the earlier app's player menu. Display only: system media controls are unaffected.
struct PlayerDisplay {
    static let totalTrackKey = "previewTotalTrack"
    static let scaleElapsedKey = "previewScaleElapsedBySpeed"
    static let lockKey = "previewLockPlayerControls"

    let range: ClosedRange<Double>
    let elapsed: Double
    let remaining: Double
    /// The whole book alongside a chapter track.
    let total: (fraction: Double, elapsed: Double, remaining: Double)?

    @MainActor init(player: ApplePlayback, at time: Double, totalTrack: Bool, scaleElapsed: Bool) {
        let duration = max(player.session?.duration ?? 0, 0)
        let speed = player.speed > 0 ? Double(player.speed) : 1
        let elapsedScale = scaleElapsed ? speed : 1
        if let window = player.mediaChapterWindow {
            range = window.start...window.end
            total = totalTrack ? (duration > 0 ? min(max(time / duration, 0), 1) : 0, max(time, 0) / elapsedScale, max(duration - time, 0) / speed) : nil
        } else {
            range = 0...max(duration, 1)
            total = nil
        }
        elapsed = max(time - range.lowerBound, 0) / elapsedScale
        remaining = max(range.upperBound - time, 0) / speed
    }
}

enum ListeningPanel: String, Identifiable {
    case chapters, speed, bookmarks, sleep, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .chapters: return "Chapters"; case .speed: return "Speed"; case .bookmarks: return "Bookmarks"; case .sleep: return "Sleep"; case .settings: return "Settings" }
    }
}

private struct ListeningControlLabelStyle: LabelStyle {
    let stacked: Bool
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if stacked {
            VStack(spacing: 8) { configuration.icon.font(.title2); configuration.title }
        } else {
            HStack(spacing: 12) { configuration.icon.font(.title2); configuration.title; Spacer(minLength: 0) }
        }
    }
}

struct ListeningControls: View {
    @EnvironmentObject private var player: ApplePlayback
    @Binding var panel: ListeningPanel?
    @AppStorage(PlayerDisplay.totalTrackKey) private var totalTrack = true
    @AppStorage(PlayerDisplay.scaleElapsedKey) private var scaleElapsed = true
    @AppStorage(PlayerDisplay.lockKey) private var locked = false
    @Environment(\.nativeStrings) private var l10n
    @State private var bookmarkTitle = ""
    @State private var editing: Bookmark?
    @State private var seconds = ""
    var body: some View {
        NativeNavigation {
            ShelfForm {
                switch panel {
                case .chapters:
                    ForEach(player.session?.chapters ?? []) { chapter in
                        Button {
                            NativeHaptic.impact("chapter")
                            Task { await player.skip(chapter.start - player.currentTime) }
                            panel = nil
                        } label: {
                            HStack { Text(chapter.title); Spacer(); Text(ShelfTime.describe(chapter.start)).foregroundColor(ShelfStyle.secondaryText) }
                        }.accessibilityIdentifier("chapter-\(chapter.id)")
                    }
                case .speed:
                    ForEach([0.5, 1, 1.2, 1.5, 1.7, 2, 3], id: \.self) { rate in
                        Button(String(format: "%g×", rate)) { player.speed = Float(rate); player.changeSpeed(); panel = nil }
                            .accessibilityIdentifier(String(format: "speed-%g", rate))
                    }
                    Stepper(value: Binding(get: { Double(player.speed) }, set: { player.speed = Float($0); player.changeSpeed() }), in: 0.5...10, step: 0.1) {
                        Text(l10n("Custom speed: {0}×", String(format: "%.1f", player.speed)))
                    }
                case .bookmarks:
                    Section(header: Text(l10n(editing == nil ? "Add a bookmark here" : "Edit bookmark")).foregroundColor(ShelfStyle.secondaryText)) {
                        TextField(l10n("Note"), text: $bookmarkTitle).accessibilityIdentifier("bookmark-title")
                        Button(l10n("Save bookmark")) {
                            NativeHaptic.impact("bookmark")
                            Task {
                                await player.saveBookmark(title: bookmarkTitle, editing: editing)
                                if player.bookmarkError == nil { bookmarkTitle = ""; editing = nil }
                            }
                        }.disabled(bookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || player.bookmarkBusy)
                    }
                    if let error = player.bookmarkError {
                        Text(error).foregroundColor(.red)
                        Button(l10n("Retry bookmarks")) { Task { await player.loadBookmarks() } }
                    }
                    if player.bookmarks.isEmpty { Text(l10n("No bookmarks yet")).foregroundColor(ShelfStyle.secondaryText) }
                    ForEach(player.bookmarks) { bookmark in
                        VStack(alignment: .leading, spacing: 12) {
                            Button(bookmark.title) { NativeHaptic.impact("bookmark"); Task { await player.skip(bookmark.time - player.currentTime) }; panel = nil }
                            Text(ShelfTime.describe(bookmark.time)).font(.caption).foregroundColor(ShelfStyle.secondaryText)
                            HStack {
                                Button(l10n("Edit")) { editing = bookmark; bookmarkTitle = bookmark.title }.accessibilityLabel(l10n("Edit {0}", bookmark.title))
                                Spacer()
                                Button(l10n("Delete")) { NativeHaptic.impact("bookmark"); Task { await player.deleteBookmark(bookmark) } }.foregroundColor(.red).accessibilityLabel(l10n("Delete {0}", bookmark.title))
                            }.font(.caption)
                        }.buttonStyle(BorderlessButtonStyle()).disabled(player.bookmarkBusy)
                    }
                case .sleep:
                    if player.sleepRemaining != nil || player.sleepChapterEnd != nil {
                        Section(header: Text(l10n("Active timer")).foregroundColor(ShelfStyle.secondaryText)) {
                            if let remaining = player.sleepRemaining {
                                Text(l10n("Sleep in {0}", ShelfTime.describe(remaining)))
                                Button(l10n("Add 5 minutes")) { NativeHaptic.impact("sleep-timer"); player.adjustSleepTimer(by: 300) }
                                Button(l10n("Subtract 5 minutes")) { NativeHaptic.impact("sleep-timer"); player.adjustSleepTimer(by: -300) }
                            } else { Text(l10n("Sleep at chapter end")) }
                            Button(l10n("Reset timer")) { NativeHaptic.impact("sleep-timer"); player.resetSleepTimer(); panel = nil }
                            Button(l10n("Cancel timer")) { NativeHaptic.impact("sleep-timer"); player.cancelSleepTimer(); panel = nil }
                        }
                    }
                    Toggle(l10n("Fade audio in the last minute"), isOn: $player.fadeSleepTimer)
                    if player.sleepRemaining != nil { Text(l10n("Audio volume: {0}%", Int(player.audioVolume * 100))).accessibilityIdentifier("fade-volume") }
                    Section(header: Text(l10n("Sleep after listening")).foregroundColor(ShelfStyle.secondaryText)) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                            Button(l10n("{0} minutes", minutes)) { NativeHaptic.impact("sleep-timer"); player.setSleepTimer(seconds: Double(minutes * 60)); panel = nil }
                        }
                        TextField(l10n("Custom duration in seconds"), text: $seconds).keyboardType(.numberPad).accessibilityIdentifier("timer-seconds")
                        Button(l10n("Start timer")) { if let duration = Double(seconds) { NativeHaptic.impact("sleep-timer"); player.setSleepTimer(seconds: duration); panel = nil } }
                            .disabled((Double(seconds) ?? 0) <= 0)
                        Button(l10n("End of chapter")) { NativeHaptic.impact("sleep-timer"); player.setChapterSleepTimer(); panel = nil }.disabled(player.currentChapter == nil)
                    }
                case .settings:
                    // As in the earlier app, turning one track off turns the other on, so a track always stays visible.
                    Toggle(l10n("Chapter track"), isOn: Binding(get: { player.chapterTrack }, set: { player.chapterTrack = $0; if !$0 { totalTrack = true } }))
                        .accessibilityIdentifier("chapter-track-setting")
                    Toggle(l10n("Total track"), isOn: Binding(get: { totalTrack }, set: { totalTrack = $0; if !$0 { player.chapterTrack = true } }))
                        .accessibilityIdentifier("total-track-setting")
                    Toggle(l10n("Scale elapsed time by speed"), isOn: $scaleElapsed).accessibilityIdentifier("scale-elapsed-setting")
                    Toggle(l10n("Lock player"), isOn: $locked).accessibilityIdentifier("lock-player")
                    Toggle(l10n("Rewind after a pause"), isOn: $player.rewindAfterPause)
                    Toggle(l10n("Allow seeking from system media controls"), isOn: $player.allowMediaSeeking)
                    Picker(l10n("Forward interval"), selection: $player.forwardInterval) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in Text(l10n("{0} seconds", seconds)).tag(seconds) }
                    }.pickerStyle(MenuPickerStyle()).accessibilityIdentifier("Forward interval")
                    Picker(l10n("Backward interval"), selection: $player.backwardInterval) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in Text(l10n("{0} seconds", seconds)).tag(seconds) }
                    }.pickerStyle(MenuPickerStyle()).accessibilityIdentifier("Backward interval")
                    Toggle(l10n("Fade audio in the last minute"), isOn: $player.fadeSleepTimer)
                case nil: EmptyView()
                }
            }.navigationTitle(l10n(panel?.title ?? "Listening"))
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(l10n("Done")) { panel = nil }.accessibilityIdentifier("panel-done") } }
        }.onAppear { if panel == .bookmarks { Task { await player.loadBookmarks() } } }
    }
}

@MainActor @ViewBuilder func playbackToggle(_ player: ApplePlayback, large: Bool = false, prefix: String? = nil, strings: NativeStrings = .current) -> some View {
    Button { NativeHaptic.impact("play"); player.toggle() } label: {
        Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill")
            .font(large ? .system(size: 34) : .title2)
            .frame(width: large ? 80 : 44, height: large ? 80 : 44)
            .foregroundColor(large ? .white : ShelfStyle.accent)
            .clipShape(Circle())
    }.modifier(PlaybackToggleStyle(large: large)).accessibilityLabel(strings(player.wantsPlayback ? "Pause" : "Play"))
        .accessibilityIdentifier((prefix ?? (large ? "" : "mini-")) + (player.wantsPlayback ? "pause-playback" : "resume-playback"))
}

private struct PlaybackToggleStyle: ViewModifier {
    let large: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if large {
            if #available(iOS 26, *) { content.nativeGlassButton(prominent: true).tint(ShelfStyle.accentFill).buttonBorderShape(.circle) }
            else { content.buttonStyle(PlainButtonStyle()).nativeGlassControl(tint: ShelfStyle.accentFill, cornerRadius: 40) }
        }
        else { content.buttonStyle(PlainButtonStyle()) }
    }
}

private struct CompactPlayerHeight: PreferenceKey {
    static var defaultValue: CGFloat = 96
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
