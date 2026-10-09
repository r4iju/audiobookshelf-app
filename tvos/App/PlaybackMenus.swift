import SwiftUI

/// Menu identity must outlive playback clock ticks, or tvOS reconstructs the focused native row.
struct PlaybackSpeedMenu: View, Equatable {
    @Environment(\.nativeStrings) private var l10n
    let player: TVPlayer
    let speed: Float
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.player === rhs.player && lhs.speed == rhs.speed
    }

    var body: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { value in
                Button(Format.speed(value)) { player.speed = value; player.changeSpeed() }
            }
        } label: { Label(l10n("Speed {0}", Format.speed(speed)), systemImage: "speedometer") }
        .accessibilityIdentifier("playback-speed")
        .accessibilityLabel(l10n("Speed {0}", Format.speed(speed)))
    }
}

struct PlaybackSleepMenu: View, Equatable {
    @Environment(\.nativeStrings) private var l10n
    let player: TVPlayer
    let hasChapter: Bool
    let timerActive: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.player === rhs.player && lhs.hasChapter == rhs.hasChapter && lhs.timerActive == rhs.timerActive
    }

    var body: some View {
        Menu {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button(l10n("{0} minutes", minutes)) { player.setSleepTimer(seconds: Double(minutes * 60)) }
            }
            if hasChapter { Button(l10n("End of chapter")) { player.setChapterSleepTimer() } }
            if timerActive {
                Button(l10n("Turn off sleep timer"), role: .destructive) { player.cancelSleepTimer() }
            }
        } label: { Label(l10n("Sleep timer"), systemImage: "moon.zzz") }
        .accessibilityIdentifier("sleep-timer")
        .accessibilityLabel(l10n("Sleep timer"))
    }
}
