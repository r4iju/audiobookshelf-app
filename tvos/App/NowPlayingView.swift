import SwiftUI

/// The shared session's controls. Leaving this tab never closes playback; only Stop does.
struct NowPlayingView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @Environment(\.nativeStrings) private var l10n
    @State private var showChapters = false
    @State private var stopError: String?
    @State private var savesWaiting = false
    @State private var restartError: String?
    @State private var restarting = false

    var body: some View {
        ScrollView {
            playbackContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showChapters) { chapters.tvLocalization() }
        .onChange(of: player.session?.id) { stopError = nil; restartError = nil }
        .task(id: [player.itemID ?? "", player.episodeID ?? ""]) { await refreshWaiting() }
        .onReceive(NotificationCenter.default.publisher(for: PublicationLedger.changed)) { _ in Task { await refreshWaiting() } }
    }

    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 44) {
            HStack(alignment: .top, spacing: 70) {
                if let id = player.itemID {
                    CoverView(itemID: id).frame(width: 460, height: 460).clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    PlaybackStatus(player: player, clock: player.clock)
                    Text(player.title).font(.system(size: 50, weight: .bold)).lineLimit(3)
                        .accessibilityIdentifier("now-playing-title")
                    Text(player.author).font(.title3).foregroundStyle(.secondary)
                    PlaybackTimeline(player: player, clock: player.clock)
                    transport.padding(.top, 20).focusSection()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            options
                .nativeGlassButton()
                .frame(maxWidth: .infinity)
                .focusSection()
            if savesWaiting {
                Text(l10n("An earlier save of this title got no answer, so newer listening stays on this TV. Settings shows how to send it."))
                    .foregroundStyle(.secondary).accessibilityIdentifier("now-playing-saves-waiting")
            }
            if let error = stopError ?? restartError ?? player.error {
                HStack(spacing: 30) {
                    Text(error).foregroundStyle(.orange).accessibilityIdentifier("playback-error")
                    if player.needsSignIn {
                        Button(l10n("Sign in again")) { catalog.needsSignIn = true }
                    } else if stopError != nil || player.isProgressFailure {
                        Button(l10n("Save progress again")) { stopError = nil; player.sync() }.accessibilityIdentifier("retry-sync")
                    } else {
                        Button(restarting ? l10n("Restarting…") : l10n("Restart playback")) { Task { await restartMedia() } }
                            .accessibilityIdentifier("restart-playback")
                            .disabled(restarting || player.preparing || player.seeking)
                    }
                }
                .focusSection()
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 50)
    }

    private func refreshWaiting() async {
        guard let itemID = player.itemID, let account = try? await catalog.api.currentAccount() else { savesWaiting = false; return }
        savesWaiting = player.publications.unanswered(account: account, itemID: itemID, episodeID: player.episodeID)
    }

    private var chapter: PlaybackChapter? {
        PlaybackChapter(chapters: player.session?.chapters, time: player.currentTime)
    }

    private var transport: some View {
        let busy = player.preparing
        return HStack(spacing: 36) {
            Button { jump(chapterOffset: -1) } label: { Image(systemName: "backward.end.fill") }
                .accessibilityIdentifier("previous-chapter").accessibilityLabel(l10n("Previous chapter"))
                .disabled(chapter == nil)
            Button { Task { await player.skip(-Double(player.backwardInterval)) } } label: { Image(systemName: Self.skipSymbol("gobackward", player.backwardInterval)) }
                .accessibilityIdentifier("skip-back").accessibilityLabel(l10n("Back {0} seconds", player.backwardInterval))
            Button { player.toggle() } label: {
                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill").frame(width: 100, height: 54)
            }
            .nativeGlassButton(prominent: true)
            .accessibilityIdentifier("toggle-playback").accessibilityLabel(player.wantsPlayback ? l10n("Pause") : l10n("Play"))
            Button { Task { await player.skip(Double(player.forwardInterval)) } } label: { Image(systemName: Self.skipSymbol("goforward", player.forwardInterval)) }
                .accessibilityIdentifier("skip-forward").accessibilityLabel(l10n("Forward {0} seconds", player.forwardInterval))
            Button { jump(chapterOffset: 1) } label: { Image(systemName: "forward.end.fill") }
                .accessibilityIdentifier("next-chapter").accessibilityLabel(l10n("Next chapter"))
                .disabled(chapter.map { $0.index + 1 >= $0.count } ?? true)
        }
        .font(.title2)
        .nativeGlassButton()
        .disabled(busy)
    }

    private var options: some View {
        HStack(spacing: 30) {
            if chapter != nil {
                Button { showChapters = true } label: { Label(l10n("Chapters"), systemImage: "list.bullet") }
                    .accessibilityIdentifier("chapters")
            }
            PlaybackSpeedMenu(player: player, speed: player.speed).equatable()
            PlaybackSleepMenu(player: player, hasChapter: chapter != nil,
                              timerActive: player.sleepRemaining != nil || player.sleepChapterEnd != nil).equatable()
            Button(role: .destructive) {
                Task {
                    do { stopError = nil; try await player.stop() }
                    catch {
                        catalog.noteAuthentication(error)
                        TVDiagnostics.shared.record(error, detail: "Stop")
                        stopError = l10n("Playback progress could not be saved: {0}", CatalogStore.recovery(for: error, in: l10n))
                    }
                }
            } label: { Label(l10n("Stop"), systemImage: "stop.fill") }
                .accessibilityIdentifier("stop-playback")
                .disabled(player.preparing)
        }
    }

    private func restartMedia() async {
        restarting = true; restartError = nil
        defer { restarting = false }
        restartError = await MediaRestart.run(player, account: { catalog.accountID }, fetch: catalog.api.item(id:))
    }

    private var chapters: some View {
        NavigationStack {
            List(Array((player.session?.chapters ?? []).enumerated()), id: \.element.id) { index, item in
                Button {
                    seek(to: item.start)
                    showChapters = false
                } label: {
                    HStack {
                        Text(item.title)
                        Spacer()
                        if chapter?.index == index { Image(systemName: "speaker.wave.2.fill") }
                        Text(Format.clock(item.start)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(l10n("Chapters"))
        }
    }

    private func jump(chapterOffset: Int) {
        guard let current = chapter, let chapters = player.session?.chapters else { return }
        var target = current.index + chapterOffset
        if chapterOffset < 0 && player.currentTime - current.chapter.start > 3 { target = current.index }
        guard chapters.indices.contains(target) else { return }
        seek(to: chapters[target].start)
    }

    private func seek(to time: Double) {
        Task {
            do { try await player.seek(to: time, autoplay: player.wantsPlayback) }
            catch is CancellationError {}
            catch { player.error = CatalogStore.recovery(for: error, in: l10n) }
        }
    }

    private static func skipSymbol(_ base: String, _ seconds: Int) -> String {
        [5, 10, 15, 30, 45, 60, 75, 90].contains(seconds) ? "\(base).\(seconds)" : base
    }
}
