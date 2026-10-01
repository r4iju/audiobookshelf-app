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
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            HStack(alignment: .top, spacing: 70) {
                if let id = player.itemID {
                    CoverView(itemID: id).frame(width: 460, height: 460).clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text(status).font(.caption.bold()).tracking(3).foregroundStyle(.tint)
                        .accessibilityIdentifier("playback-status").accessibilityLabel(status)
                    Text(player.title).font(.system(size: 50, weight: .bold)).lineLimit(3)
                        .accessibilityIdentifier("now-playing-title")
                    Text(player.author).font(.title3).foregroundStyle(.secondary)
                    if let chapter = chapter {
                        Text(l10n("{0} · Chapter {1} of {2}", chapter.chapter.title, chapter.index + 1, chapter.count)).font(.headline)
                            .accessibilityIdentifier("now-playing-chapter")
                        let elapsed = min(max(player.currentTime - chapter.chapter.start, 0), chapter.length)
                        progress(l10n("Chapter progress"), identifier: "chapter-progress", elapsed: elapsed, length: chapter.length)
                    }
                    if let session = player.session {
                        progress(l10n("Book progress"), identifier: "total-progress", elapsed: min(player.currentTime, session.duration), length: session.duration, tint: .orange)
                        let remaining = max(session.duration - player.currentTime, 0)
                        HStack {
                            Text(Format.clock(player.currentTime)).accessibilityIdentifier("now-playing-elapsed")
                            Spacer()
                            Text("−" + Format.clock(remaining)).accessibilityIdentifier("now-playing-remaining")
                        }
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let remaining = player.sleepRemaining {
                        Label(l10n("Sleep in {0}", Format.clock(remaining)), systemImage: "moon.zzz").foregroundStyle(.secondary)
                    } else if player.sleepChapterEnd != nil {
                        Label(l10n("Sleep at end of chapter"), systemImage: "moon.zzz").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            transport.focusSection()
            options.focusSection()
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
        .sheet(isPresented: $showChapters) { chapters.tvLocalization() }
        .onChange(of: player.session?.id) { stopError = nil; restartError = nil }
        .task(id: [player.itemID ?? "", player.episodeID ?? ""]) { await refreshWaiting() }
        .onReceive(NotificationCenter.default.publisher(for: PublicationLedger.changed)) { _ in Task { await refreshWaiting() } }
    }

    private func refreshWaiting() async {
        guard let itemID = player.itemID, let account = try? await catalog.api.currentAccount() else { savesWaiting = false; return }
        savesWaiting = player.publications.unresolved(account: account, itemID: itemID, episodeID: player.episodeID)
    }

    private var status: String {
        guard let session = player.session else { return l10n("Stopped") }
        if player.preparing { return l10n("Loading") }
        if !player.wantsPlayback && player.currentTime >= session.duration - 0.5 { return l10n("Finished") }
        if player.playing { return l10n("Playing") }
        return player.wantsPlayback ? l10n("Buffering") : l10n("Paused")
    }

    /// One element for VoiceOver, read as the time left rather than a bare percentage.
    private func progress(_ title: String, identifier: String, elapsed: Double, length: Double, tint: Color? = nil) -> some View {
        ProgressView(value: elapsed, total: max(length, 1)).tint(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(l10n("{0} remaining", Format.spoken(max(length - elapsed, 0), locale: l10n.language.locale)))
            .accessibilityIdentifier(identifier)
    }

    private var chapter: (chapter: Chapter, index: Int, count: Int, length: Double)? {
        guard let chapters = player.session?.chapters, !chapters.isEmpty else { return nil }
        let index = chapters.lastIndex { $0.start <= player.currentTime } ?? 0
        return (chapters[index], index, chapters.count, chapters[index].end - chapters[index].start)
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
                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill").frame(width: 80)
            }
            .accessibilityIdentifier("toggle-playback").accessibilityLabel(player.wantsPlayback ? l10n("Pause") : l10n("Play"))
            Button { Task { await player.skip(Double(player.forwardInterval)) } } label: { Image(systemName: Self.skipSymbol("goforward", player.forwardInterval)) }
                .accessibilityIdentifier("skip-forward").accessibilityLabel(l10n("Forward {0} seconds", player.forwardInterval))
            Button { jump(chapterOffset: 1) } label: { Image(systemName: "forward.end.fill") }
                .accessibilityIdentifier("next-chapter").accessibilityLabel(l10n("Next chapter"))
                .disabled(chapter.map { $0.index + 1 >= $0.count } ?? true)
        }
        .font(.title2)
        .disabled(busy)
    }

    private var options: some View {
        HStack(spacing: 30) {
            if chapter != nil {
                Button { showChapters = true } label: { Label(l10n("Chapters"), systemImage: "list.bullet") }
                    .accessibilityIdentifier("chapters")
            }
            Menu {
                ForEach(Self.speeds, id: \.self) { speed in
                    Button(Format.speed(speed)) { player.speed = speed; player.changeSpeed() }
                }
            } label: { Label(l10n("Speed {0}", Format.speed(player.speed)), systemImage: "speedometer") }
                .accessibilityIdentifier("playback-speed").accessibilityLabel(l10n("Speed {0}", Format.speed(player.speed)))
            Menu {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button(l10n("{0} minutes", minutes)) { player.setSleepTimer(seconds: Double(minutes * 60)) }
                }
                if chapter != nil { Button(l10n("End of chapter")) { player.setChapterSleepTimer() } }
                if player.sleepRemaining != nil || player.sleepChapterEnd != nil {
                    Button(l10n("Turn off sleep timer"), role: .destructive) { player.cancelSleepTimer() }
                }
            } label: { Label(l10n("Sleep timer"), systemImage: "moon.zzz") }
                .accessibilityIdentifier("sleep-timer")
                .accessibilityLabel(l10n("Sleep timer"))
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
