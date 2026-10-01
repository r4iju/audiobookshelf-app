import SwiftUI

struct PlaybackContainer<Content: View>: View {
    @EnvironmentObject private var player: ApplePlayback
    @State private var expanded = false
    let content: Content
    var body: some View {
        content.padding(.bottom, player.session == nil && !player.preparing ? 0 : 86)
            .overlay(miniPlayer, alignment: .bottom)
            .sheet(isPresented: $expanded) { NowListening().environmentObject(player) }
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
    @EnvironmentObject private var player: ApplePlayback
    @Environment(\.presentationMode) private var presentation
    @State private var scrubbing = false
    @State private var position: Double = 0
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32).fill(ShelfStyle.accent.opacity(0.12))
                        Image(systemName: "books.vertical.fill").font(.system(size: 90)).foregroundColor(ShelfStyle.accent)
                    }.frame(width: 220, height: 260).padding(.top, 20)
                    VStack(spacing: 10) {
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
                        Button { Task { await player.skip(-30) } } label: { Image(systemName: "gobackward.30").font(.largeTitle) }.accessibilityLabel("Back 30 seconds")
                        playbackToggle(player, large: true)
                        Button { Task { await player.skip(30) } } label: { Image(systemName: "goforward.30").font(.largeTitle) }.accessibilityLabel("Forward 30 seconds")
                    }.foregroundColor(ShelfStyle.accent)
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
