import SwiftUI

enum Format {
    static func clock(_ seconds: Double) -> String {
        let value = Int(max(seconds.isFinite ? seconds : 0, 0).rounded(.down))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(seconds.isFinite ? seconds : 0, 0)) / 60
        if minutes == 0 { return clock(seconds) }
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    static func speed(_ value: Float) -> String { String(format: "%g", value) + "×" }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<br ?/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func published(_ milliseconds: Double?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    /// Listening state for an item or episode, or nil when it has not been started.
    static func facts(_ episode: Episode) -> String {
        [published(episode.publishedAt), episode.playableDuration.map(duration)].compactMap { $0 }.joined(separator: " · ")
    }

    static func progress(_ progress: MediaProgress?, duration: Double?) -> String? {
        guard let progress else { return nil }
        if progress.isFinished == true { return "Finished" }
        guard let position = progress.currentTime, position > 0 else { return nil }
        let total = progress.duration ?? duration ?? 0
        return total > 0 ? "\(clock(position)) of \(clock(total)) listened" : "\(clock(position)) listened"
    }
}

struct CoverView: View {
    @EnvironmentObject private var catalog: CatalogStore
    let itemID: String
    var podcast = false
    @State private var cover: UIImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            if let cover { Image(uiImage: cover).resizable().scaledToFill() }
            else if loaded {
                Image(systemName: podcast ? "mic.fill" : "book.closed.fill")
                    .font(.system(size: 64)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("cover-placeholder")
            }
        }
        .clipped()
        .accessibilityHidden(cover == nil && !loaded)
        .task(id: itemID) {
            cover = await catalog.cover(itemID: itemID)
            loaded = true
        }
    }
}

/// A focusable cover with title, author and listening state that stays legible across the room.
struct ItemTile: View {
    @EnvironmentObject private var catalog: CatalogStore
    let item: LibraryItem
    var width: CGFloat = 260

    var body: some View {
        let state = catalog.progress(itemID: item.id, episodeID: item.isPodcast ? item.recentEpisode?.id : nil)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                CoverView(itemID: item.id, podcast: item.isPodcast)
                if state?.isFinished == true {
                    HStack { Spacer(); Image(systemName: "checkmark.circle.fill").font(.title2).padding(10) }
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if let fraction = state?.progress, fraction > 0 {
                    GeometryReader { geometry in
                        Capsule().fill(.tint).frame(width: geometry.size.width * fraction, height: 6)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(item.title).font(.system(size: 26, weight: .semibold)).lineLimit(2)
                .frame(width: width, height: 68, alignment: .topLeading)
            Text(item.author.isEmpty ? " " : item.author).font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

struct StatusMessage: View {
    let text: String
    var identifier = "catalog-error"
    var retryIdentifier = "retry-catalog"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1100)
                .accessibilityIdentifier(identifier)
            Button("Try again", action: retry).accessibilityIdentifier(retryIdentifier)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }
}

extension LibraryItem { var isPodcast: Bool { mediaType == "podcast" } }
extension Library { var isPodcast: Bool { mediaType == "podcast" } }
extension Episode { var playableDuration: Double? { duration ?? audioFile?.duration } }

enum TileGrid {
    static let columns = [GridItem(.adaptive(minimum: 260, maximum: 260), spacing: 48, alignment: .top)]
}

enum Route: Hashable {
    case item(LibraryItem)
    case episode(LibraryItem, episodeID: String)

    /// Search and shelf results for podcasts carry the matched episode; open it directly.
    static func to(_ item: LibraryItem) -> Route {
        if let episode = item.recentEpisode, item.isPodcast { return .episode(item, episodeID: episode.id) }
        return .item(item)
    }
}
