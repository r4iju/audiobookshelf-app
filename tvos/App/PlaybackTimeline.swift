import SwiftUI

struct PlaybackStatus: View {
    @Environment(\.nativeStrings) private var l10n
    @ObservedObject var player: TVPlayer
    @ObservedObject var clock: TVPlaybackClock

    var body: some View {
        Text(status).font(.caption.bold()).tracking(3).foregroundStyle(.tint)
            .accessibilityIdentifier("playback-status").accessibilityLabel(status)
    }

    private var status: String {
        guard let session = player.session else { return l10n("Stopped") }
        if player.preparing { return l10n("Loading") }
        if !player.wantsPlayback && clock.currentTime >= session.duration - 0.5 { return l10n("Finished") }
        if player.playing { return l10n("Playing") }
        return player.wantsPlayback ? l10n("Buffering") : l10n("Paused")
    }
}

struct PlaybackTimeline: View {
    @Environment(\.nativeStrings) private var l10n
    @ObservedObject var player: TVPlayer
    @ObservedObject var clock: TVPlaybackClock

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let chapter {
                Text(l10n("{0} · Chapter {1} of {2}", chapter.chapter.title, chapter.index + 1, chapter.count)).font(.headline)
                    .accessibilityIdentifier("now-playing-chapter")
                let elapsed = min(max(clock.currentTime - chapter.chapter.start, 0), chapter.length)
                progress(l10n("Chapter progress"), identifier: "chapter-progress", elapsed: elapsed, length: chapter.length)
            }
            if let session = player.session {
                progress(l10n("Book progress"), identifier: "total-progress", elapsed: min(clock.currentTime, session.duration), length: session.duration, tint: .orange)
                HStack {
                    Text(Format.clock(clock.currentTime)).accessibilityIdentifier("now-playing-elapsed")
                    Spacer()
                    Text("−" + Format.clock(max(session.duration - clock.currentTime, 0))).accessibilityIdentifier("now-playing-remaining")
                }
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let remaining = clock.sleepRemaining {
                Label(l10n("Sleep in {0}", Format.clock(remaining)), systemImage: "moon.zzz").foregroundStyle(.secondary)
            } else if player.sleepChapterEnd != nil {
                Label(l10n("Sleep at end of chapter"), systemImage: "moon.zzz").foregroundStyle(.secondary)
            }
        }
    }

    /// One element for VoiceOver, read as the time left rather than a bare percentage.
    private func progress(_ title: String, identifier: String, elapsed: Double, length: Double, tint: Color? = nil) -> some View {
        ProgressView(value: elapsed, total: max(length, 1)).tint(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(l10n("{0} remaining", Format.spoken(max(length - elapsed, 0), locale: l10n.language.locale)))
            .accessibilityIdentifier(identifier)
    }

    private var chapter: PlaybackChapter? {
        PlaybackChapter(chapters: player.session?.chapters, time: clock.currentTime)
    }

}

struct PlaybackChapter {
    let chapter: Chapter
    let index: Int
    let count: Int
    var length: Double { chapter.end - chapter.start }

    init?(chapters: [Chapter]?, time: Double) {
        guard let chapters, !chapters.isEmpty else { return nil }
        index = chapters.lastIndex { $0.start <= time } ?? 0
        chapter = chapters[index]
        count = chapters.count
    }
}
