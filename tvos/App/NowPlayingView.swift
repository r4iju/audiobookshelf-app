import SwiftUI

/// The shared session's controls. Leaving this tab never closes playback; only Stop does.
struct NowPlayingView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: TVPlayer
    @State private var showChapters = false
    @State private var stopError: String?
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            HStack(alignment: .top, spacing: 70) {
                if let id = player.itemID {
                    CoverView(itemID: id).frame(width: 460, height: 460).clipShape(RoundedRectangle(cornerRadius: 24))
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text(status).font(.caption.bold()).tracking(3).foregroundStyle(.tint)
                        .accessibilityIdentifier("playback-status").accessibilityLabel(status)
                    Text(player.title).font(.system(size: 50, weight: .bold)).lineLimit(3)
                        .accessibilityIdentifier("now-playing-title")
                    Text(player.author).font(.title3).foregroundStyle(.secondary)
                    if let chapter = chapter {
                        Text("\(chapter.chapter.title) · Chapter \(chapter.index + 1) of \(chapter.count)").font(.headline)
                            .accessibilityIdentifier("now-playing-chapter")
                        ProgressView(value: min(max(player.currentTime - chapter.chapter.start, 0), chapter.length), total: max(chapter.length, 1))
                    }
                    if let session = player.session {
                        ProgressView(value: min(player.currentTime, session.duration), total: max(session.duration, 1)).tint(.orange)
                        HStack {
                            Text(Format.clock(player.currentTime)).accessibilityIdentifier("now-playing-elapsed")
                            Spacer()
                            Text("−" + Format.clock(max(session.duration - player.currentTime, 0))).accessibilityIdentifier("now-playing-remaining")
                        }
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let remaining = player.sleepRemaining {
                        Label("Sleep in \(Format.clock(remaining))", systemImage: "moon.zzz").foregroundStyle(.secondary)
                    } else if player.sleepChapterEnd != nil {
                        Label("Sleep at end of chapter", systemImage: "moon.zzz").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            transport.focusSection()
            options.focusSection()
            if let error = stopError ?? player.error {
                HStack(spacing: 30) {
                    Text(error).foregroundStyle(.orange).accessibilityIdentifier("playback-error")
                    if player.needsSignIn {
                        Button("Sign in again") { catalog.needsSignIn = true }
                    } else {
                        Button("Save progress again") { stopError = nil; player.sync() }.accessibilityIdentifier("retry-sync")
                    }
                }
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 50)
        .sheet(isPresented: $showChapters) { chapters }
    }

    private var status: String {
        guard let session = player.session else { return "Stopped" }
        if player.preparing { return "Loading" }
        if !player.wantsPlayback && player.currentTime >= session.duration - 0.5 { return "Finished" }
        if player.playing { return "Playing" }
        return player.wantsPlayback ? "Buffering" : "Paused"
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
                .accessibilityIdentifier("previous-chapter").accessibilityLabel("Previous chapter")
                .disabled(chapter == nil)
            Button { Task { await player.skip(-Double(player.backwardInterval)) } } label: { Image(systemName: Self.skipSymbol("gobackward", player.backwardInterval)) }
                .accessibilityIdentifier("skip-back").accessibilityLabel("Back \(player.backwardInterval) seconds")
            Button { player.toggle() } label: {
                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill").frame(width: 80)
            }
            .accessibilityIdentifier("toggle-playback").accessibilityLabel(player.wantsPlayback ? "Pause" : "Play")
            Button { Task { await player.skip(Double(player.forwardInterval)) } } label: { Image(systemName: Self.skipSymbol("goforward", player.forwardInterval)) }
                .accessibilityIdentifier("skip-forward").accessibilityLabel("Forward \(player.forwardInterval) seconds")
            Button { jump(chapterOffset: 1) } label: { Image(systemName: "forward.end.fill") }
                .accessibilityIdentifier("next-chapter").accessibilityLabel("Next chapter")
                .disabled(chapter.map { $0.index + 1 >= $0.count } ?? true)
        }
        .font(.title2)
        .disabled(busy)
    }

    private var options: some View {
        HStack(spacing: 30) {
            if chapter != nil {
                Button { showChapters = true } label: { Label("Chapters", systemImage: "list.bullet") }
                    .accessibilityIdentifier("chapters")
            }
            Menu {
                ForEach(Self.speeds, id: \.self) { speed in
                    Button(Format.speed(speed)) { player.speed = speed; player.changeSpeed() }
                }
            } label: { Label("Speed \(Format.speed(player.speed))", systemImage: "speedometer") }
                .accessibilityIdentifier("playback-speed").accessibilityLabel("Speed \(Format.speed(player.speed))")
            Menu {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { player.setSleepTimer(seconds: Double(minutes * 60)) }
                }
                if chapter != nil { Button("End of chapter") { player.setChapterSleepTimer() } }
                if player.sleepRemaining != nil || player.sleepChapterEnd != nil {
                    Button("Turn off sleep timer", role: .destructive) { player.cancelSleepTimer() }
                }
            } label: { Label("Sleep timer", systemImage: "moon.zzz") }
                .accessibilityIdentifier("sleep-timer")
            Button(role: .destructive) {
                Task {
                    do { stopError = nil; try await player.stop() }
                    catch {
                        catalog.noteAuthentication(error)
                        stopError = "Playback progress could not be saved: " + CatalogStore.recovery(for: error)
                    }
                }
            } label: { Label("Stop", systemImage: "stop.fill") }
                .accessibilityIdentifier("stop-playback")
                .disabled(player.preparing)
        }
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
            .navigationTitle("Chapters")
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
            catch { player.error = CatalogStore.recovery(for: error) }
        }
    }

    private static func skipSymbol(_ base: String, _ seconds: Int) -> String {
        [5, 10, 15, 30, 45, 60, 75, 90].contains(seconds) ? "\(base).\(seconds)" : base
    }
}
