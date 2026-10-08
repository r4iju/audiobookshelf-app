import SwiftUI

enum Format {
    static let longestTime: Double = 9_999 * 3600

    /// Whole seconds, with server values that are invalid or absurdly long held within what can be displayed.
    static func seconds(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value, longestTime).rounded(.down))
    }

    static func fraction(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func clock(_ seconds: Double) -> String {
        let value = Self.seconds(seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }

    static func duration(_ seconds: Double, locale: Locale = NativeLanguage.current.locale) -> String {
        let minutes = Self.seconds(seconds) / 60
        if minutes == 0 { return clock(seconds) }
        return components(TimeInterval(minutes * 60), units: [.hour, .minute], style: .short, locale: locale) ?? clock(seconds)
    }

    /// A time read out in words, such as "14 seconds", for VoiceOver rather than a clock.
    static func spoken(_ seconds: Double, locale: Locale = NativeLanguage.current.locale) -> String {
        components(TimeInterval(Self.seconds(seconds)), units: [.hour, .minute, .second], style: .full, locale: locale) ?? clock(seconds)
    }

    private static func components(_ interval: TimeInterval, units: NSCalendar.Unit, style: DateComponentsFormatter.UnitsStyle, locale: Locale) -> String? {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = units
        formatter.unitsStyle = style
        formatter.zeroFormattingBehavior = interval == 0 ? .default : .dropAll
        return formatter.string(from: interval)
    }

    static func speed(_ value: Float) -> String { String(format: "%g", value) + "×" }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<br ?/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func published(_ milliseconds: Double?, locale: Locale = NativeLanguage.current.locale) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000).formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func facts(_ episode: Episode, locale: Locale = NativeLanguage.current.locale) -> String {
        [published(episode.publishedAt, locale: locale), episode.playableDuration.map { duration($0, locale: locale) }].compactMap { $0 }.joined(separator: " · ")
    }

    /// Listening state for an item or episode, or nil when it has not been started.
    static func progress(_ progress: MediaProgress?, duration: Double?, strings: NativeStrings = .current) -> String? {
        guard let progress else { return nil }
        if progress.isFinished == true { return strings("Finished") }
        guard let position = progress.currentTime, position > 0 else { return nil }
        let total = progress.duration ?? duration ?? 0
        return total > 0 ? strings("{0} of {1} listened", clock(position), clock(total)) : strings("{0} listened", clock(position))
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
            if let cover { Image(uiImage: cover).resizable().scaledToFit() }
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
    @Environment(\.nativeStrings) private var l10n
    let item: LibraryItem
    let episodeID: String?
    private let width: CGFloat = 260

    /// Podcast tiles stand for the episode they open: the server's matched or most recent one unless given.
    init(item: LibraryItem, episodeID: String? = nil) {
        self.item = item
        self.episodeID = episodeID ?? (item.isPodcast ? item.recentEpisode?.id : nil)
    }

    var body: some View {
        let state = catalog.progress(itemID: item.id, episodeID: episodeID)
        let episode = episodeID.flatMap { id in item.recentEpisode?.id == id ? item.recentEpisode : item.media.episodes?.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                CoverView(itemID: item.id, podcast: item.isPodcast)
                if state?.isFinished == true {
                    HStack { Spacer(); Image(systemName: "checkmark.circle.fill").font(.title2).padding(10) }
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if case let fraction = Format.fraction(state?.progress), fraction > 0 {
                    GeometryReader { geometry in
                        Capsule().fill(.tint).frame(width: geometry.size.width * fraction, height: 6)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(episode?.title ?? item.title).font(.system(size: 26, weight: .semibold)).lineLimit(2)
                .frame(width: width, height: 68, alignment: .topLeading)
            Text(episode != nil ? item.title : item.author.isEmpty ? " " : item.author).font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Format.progress(state, duration: episode?.playableDuration ?? item.media.duration, strings: l10n) ?? "")
    }
}

struct StatusMessage: View {
    @Environment(\.nativeStrings) private var l10n
    let text: String
    var identifier = "catalog-error"
    var retryIdentifier = "retry-catalog"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 60)).foregroundStyle(.secondary)
            Text(text).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1100)
                .accessibilityIdentifier(identifier)
            Button(l10n("Try again"), action: retry).accessibilityIdentifier(retryIdentifier)
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
    case author(RelatedLink)
    case series(RelatedLink)

    /// Search and shelf results for podcasts carry the matched episode; open it directly.
    static func to(_ item: LibraryItem) -> Route {
        if let episode = item.recentEpisode, item.isPodcast { return .episode(item, episodeID: episode.id) }
        return .item(item)
    }
}
