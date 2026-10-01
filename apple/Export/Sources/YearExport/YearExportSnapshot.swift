#if canImport(TVCore)
import TVCore
#endif
import Foundation
import CoreGraphics

/// Mirrors the legacy share images: the three "Your Year in Review" canvases (variant 1 draws
/// finished-book covers), the short banner, and the three admin "server" canvases.
public enum YearExportDesign: String, CaseIterable, Identifiable, Sendable {
    case highlights, finishedBooks, topLists, compact, serverAdditions, serverPeople, serverGenres
    public var id: String { rawValue }
    /// English names; the composer shows `YearExportCopy.title(of:)` and `summary(of:)`.
    public var title: String { YearExportCopy.english.title(of: self) }
    public var summary: String { YearExportCopy.english.summary(of: self) }
    public var shapes: [YearExportShape] {
        switch self {
        case .compact: return [.banner]
        default: return [.square, .portrait]
        }
    }
}

public enum YearExportShape: String, CaseIterable, Identifiable, Sendable {
    case square, portrait, banner
    public var id: String { rawValue }
    public var title: String { YearExportCopy.english.title(of: self) }
    public var pixelSize: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1920)
        case .banner: return CGSize(width: 1500, height: 500)
        }
    }
}

public struct YearExportLayout: Hashable, Sendable {
    public let design: YearExportDesign
    public let shape: YearExportShape
    public init?(design: YearExportDesign, shape: YearExportShape) {
        guard design.shapes.contains(shape) else { return nil }
        self.design = design
        self.shape = shape
    }
}

/// An immutable copy of one year's statistics. Every image and share text is derived from a
/// snapshot alone, so a later fetch for another year or account can never leak into an export.
public struct YearExportSnapshot: Identifiable, Sendable {
    public struct Ranked: Sendable {
        public let name: String
        public let seconds: Double
    }

    public let id = UUID()
    public let year: Int
    public let booksFinished: Int
    public let booksListened: Int
    public let sessions: Int
    public let listeningSeconds: Double
    public let topAuthors: [Ranked]
    public let topGenres: [Ranked]
    public let narrator: Ranked?
    public let month: Ranked?
    public let longestBook: Ranked?
    let format: YearExportFormat
    let artwork: YearExportArtwork?

    /// `artwork` is used only when it was loaded for this year with the stats' own cover lists
    /// (`finishedBooksWithCovers` as primary, `booksWithCovers` as secondary); otherwise it is dropped.
    /// English text with the given locale's numbers, months and durations.
    public init?(stats: YearListeningStats, year: Int, artwork: YearExportArtwork? = nil, locale: Locale) {
        self.init(stats: stats, year: year, artwork: artwork, copy: YearExportCopy(locale: locale))
    }

    /// `copy` is kept with the snapshot, so its images and text stay in that language. English by default.
    public init?(stats: YearListeningStats, year: Int, artwork: YearExportArtwork? = nil, copy: YearExportCopy = .english) {
        guard (2000...9999).contains(year) else { return nil }
        self.year = year
        let locale = copy.locale
        format = YearExportFormat(copy: copy)
        self.artwork = artwork.flatMap {
            $0.matches(year: year, primary: stats.finishedBooksWithCovers, secondary: stats.booksWithCovers) ? $0 : nil
        }
        booksFinished = max(stats.numBooksFinished, 0)
        booksListened = max(stats.numBooksListened, 0)
        sessions = max(stats.totalListeningSessions, 0)
        listeningSeconds = YearExportFormat.clean(stats.totalListeningTime)
        topAuthors = Array(stats.topAuthors.compactMap { YearExportFormat.ranked($0.name, $0.time) }.prefix(5))
        topGenres = Array(stats.topGenres.compactMap { YearExportFormat.ranked($0.genre, $0.time) }.prefix(5))
        narrator = stats.mostListenedNarrator.flatMap { YearExportFormat.ranked($0.name, $0.time) }
        month = stats.mostListenedMonth.flatMap { value in
            guard (0..<12).contains(value.month), value.time > 0 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            return YearExportFormat.ranked(calendar.standaloneMonthSymbols[value.month], value.time)
        }
        longestBook = stats.longestAudiobookFinished.flatMap { YearExportFormat.ranked($0.title, $0.duration) }
    }

    var finishedCovers: [CGImage] { artwork?.primary ?? [] }
    /// Finished covers first, then the other books listened to, as the legacy background did.
    var mosaic: [CGImage] { finishedCovers + (artwork?.secondary ?? []) }

    public var hasListening: Bool { listeningSeconds > 0 || sessions > 0 || booksListened > 0 || booksFinished > 0 }

    public var availableLayouts: [YearExportLayout] {
        [YearExportDesign.highlights, .finishedBooks, .topLists, .compact]
            .filter { design in
                switch design {
                case .topLists: return !topAuthors.isEmpty || !topGenres.isEmpty
                case .finishedBooks: return !finishedCovers.isEmpty
                default: return true
                }
            }
            .flatMap { design in design.shapes.compactMap { YearExportLayout(design: design, shape: $0) } }
    }

    var copy: YearExportCopy { format.copy }

    public var shareText: String {
        let time = listeningTime
        var lines = [
            copy("My {0} in Audiobookshelf", String(year)),
            time.hours ? (time.one ? copy("{0} hour of listening", time.value) : copy("{0} hours of listening", time.value))
                : (time.one ? copy("{0} minute of listening", time.value) : copy("{0} minutes of listening", time.value)),
            booksFinished == 1 ? copy("{0} book finished", number(booksFinished)) : copy("{0} books finished", number(booksFinished)),
            booksListened == 1 ? copy("{0} book listened to", number(booksListened)) : copy("{0} books listened to", number(booksListened)),
            sessions == 1 ? copy("{0} listening session", number(sessions)) : copy("{0} listening sessions", number(sessions))
        ]
        if let author = topAuthors.first { lines.append(copy("Top author: {0}", author.name)) }
        if let narrator { lines.append(copy("Top narrator: {0}", narrator.name)) }
        if let genre = topGenres.first { lines.append(copy("Top genre: {0}", genre.name)) }
        return lines.joined(separator: "\n")
    }

    /// Whole hours, or whole minutes under an hour; the caller picks the matching template.
    var listeningTime: (value: String, hours: Bool, one: Bool) {
        let hours = (listeningSeconds / 3600).rounded(.down)
        if hours >= 1 { return (number(hours), true, hours == 1) }
        let minutes = (listeningSeconds / 60).rounded(.down)
        return (number(minutes), false, minutes == 1)
    }

    func number(_ value: Int) -> String { format.number(Double(value)) }
    func number(_ value: Double) -> String { format.number(value) }
    func duration(_ seconds: Double) -> String { format.duration(seconds) }
}

/// Locale-bound formatting shared by listener and server snapshots. Decoded totals can be
/// finite yet far beyond Int or Int64, so nothing here converts them to an integer type unchecked.
struct YearExportFormat: Sendable {
    let copy: YearExportCopy
    var locale: Locale { copy.locale }

    func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    /// Days, hours and minutes, like the legacy server canvas; very long totals fall back to whole days.
    func longDuration(_ seconds: Double) -> String {
        guard seconds < 1e9 else { return copy("{0} days", number((seconds / 86_400).rounded(.down))) }
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    /// The legacy `$bytesPretty`: base 1024, at most two decimals, its unit symbols, and the locale's
    /// digits. Computed in `Double`, so totals of any finite size format without overflow.
    func bytes(_ value: Double) -> String {
        let units = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
        guard value >= 1 else { return "0 Bytes" }
        let index = min(Int((log(value) / log(1024)).rounded(.down)), units.count - 1)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let scaled = value / pow(1024, Double(index))
        return "\(formatter.string(from: NSNumber(value: scaled)) ?? String(format: "%.2f", scaled)) \(units[index])"
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    static func clean(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }

    static func ranked(_ name: String, _ seconds: Double) -> YearExportSnapshot.Ranked? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : YearExportSnapshot.Ranked(name: trimmed, seconds: clean(seconds))
    }
}

public struct YearExportArtifact: Sendable {
    public let snapshotID: UUID
    public let year: Int
    public let layout: YearExportLayout
    public let pngData: Data
    public let fileName: String
    public let shareText: String
    public let accessibilityLabel: String
}
