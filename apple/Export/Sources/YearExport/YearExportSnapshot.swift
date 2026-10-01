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
    public var title: String {
        switch self {
        case .highlights: return "Highlights"
        case .topLists: return "Top Lists"
        case .compact: return "Compact"
        case .finishedBooks: return "Finished"
        case .serverAdditions: return "Additions"
        case .serverPeople: return "People"
        case .serverGenres: return "Genres"
        }
    }
    public var summary: String {
        switch self {
        case .highlights: return "Your totals with top narrator, genre, author and month."
        case .topLists: return "Your totals with your top authors and genres."
        case .compact: return "A short banner with your book counts."
        case .finishedBooks: return "Your totals with covers of books you finished."
        case .serverAdditions: return "Server totals with covers of books added this year."
        case .serverPeople: return "Server totals with top authors and narrators."
        case .serverGenres: return "Server totals with top authors and genres."
        }
    }
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
    public var title: String {
        switch self {
        case .square: return "Square"
        case .portrait: return "Story"
        case .banner: return "Banner"
        }
    }
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
    public init?(stats: YearListeningStats, year: Int, artwork: YearExportArtwork? = nil, locale: Locale = .current) {
        guard (2000...9999).contains(year) else { return nil }
        self.year = year
        format = YearExportFormat(locale: locale)
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

    public var shareText: String {
        var lines = [
            "My \(year) in Audiobookshelf",
            "\(listeningTime.value) \(listeningTime.unit) of listening",
            count(booksFinished, "book finished", "books finished"),
            count(booksListened, "book listened to", "books listened to"),
            count(sessions, "listening session", "listening sessions")
        ]
        if let author = topAuthors.first { lines.append("Top author: \(author.name)") }
        if let narrator { lines.append("Top narrator: \(narrator.name)") }
        if let genre = topGenres.first { lines.append("Top genre: \(genre.name)") }
        return lines.joined(separator: "\n")
    }

    var listeningTime: (value: String, unit: String) {
        let hours = (listeningSeconds / 3600).rounded(.down)
        if hours >= 1 { return (number(hours), hours == 1 ? "hour" : "hours") }
        let minutes = (listeningSeconds / 60).rounded(.down)
        return (number(minutes), minutes == 1 ? "minute" : "minutes")
    }

    func number(_ value: Int) -> String { format.number(Double(value)) }
    func number(_ value: Double) -> String { format.number(value) }
    func count(_ value: Int, _ singular: String, _ plural: String) -> String { format.count(value, singular, plural) }
    func duration(_ seconds: Double) -> String { format.duration(seconds) }
}

/// Locale-bound formatting shared by listener and server snapshots. Decoded totals can be
/// finite yet far beyond Int or Int64, so nothing here converts them to an integer type unchecked.
struct YearExportFormat: Sendable {
    let locale: Locale

    func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(number(Double(value))) \(value == 1 ? singular : plural)"
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
        guard seconds < 1e9 else { return "\(number((seconds / 86_400).rounded(.down))) days" }
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    /// Binary units like the legacy `$bytesPretty`; clamped below Int64 overflow.
    func bytes(_ value: Double) -> String {
        let count: Int64 = value >= 9.2e18 ? .max : Int64(max(value, 0))
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: count)
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
