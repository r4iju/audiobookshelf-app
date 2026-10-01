#if canImport(TVCore)
import TVCore
#endif
import Foundation
import CoreGraphics

/// Mirrors the legacy share images: the three "Your Year in Review" canvases (variant 1 needs
/// cover art, which the stats endpoint does not supply) and the short banner.
public enum YearExportDesign: String, CaseIterable, Identifiable, Sendable {
    case highlights, topLists, compact
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .highlights: return "Highlights"
        case .topLists: return "Top Lists"
        case .compact: return "Compact"
        }
    }
    public var summary: String {
        switch self {
        case .highlights: return "Your totals with top narrator, genre, author and month."
        case .topLists: return "Your totals with your top authors and genres."
        case .compact: return "A short banner with your book counts."
        }
    }
    public var shapes: [YearExportShape] {
        switch self {
        case .highlights, .topLists: return [.square, .portrait]
        case .compact: return [.banner]
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
    let locale: Locale

    public init?(stats: YearListeningStats, year: Int, locale: Locale = .current) {
        guard (2000...9999).contains(year) else { return nil }
        self.year = year
        self.locale = locale
        booksFinished = max(stats.numBooksFinished, 0)
        booksListened = max(stats.numBooksListened, 0)
        sessions = max(stats.totalListeningSessions, 0)
        listeningSeconds = Self.seconds(stats.totalListeningTime)
        topAuthors = Array(stats.topAuthors.compactMap { Self.ranked($0.name, $0.time) }.prefix(5))
        topGenres = Array(stats.topGenres.compactMap { Self.ranked($0.genre, $0.time) }.prefix(5))
        narrator = stats.mostListenedNarrator.flatMap { Self.ranked($0.name, $0.time) }
        month = stats.mostListenedMonth.flatMap { value in
            guard (0..<12).contains(value.month), value.time > 0 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            return Self.ranked(calendar.standaloneMonthSymbols[value.month], value.time)
        }
        longestBook = stats.longestAudiobookFinished.flatMap { Self.ranked($0.title, $0.duration) }
    }

    public var hasListening: Bool { listeningSeconds > 0 || sessions > 0 || booksListened > 0 || booksFinished > 0 }

    public var availableLayouts: [YearExportLayout] {
        YearExportDesign.allCases
            .filter { $0 != .topLists || !topAuthors.isEmpty || !topGenres.isEmpty }
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
        if hours >= 1 { return (number(Int(hours)), hours == 1 ? "hour" : "hours") }
        let minutes = Int((listeningSeconds / 60).rounded(.down))
        return (number(minutes), minutes == 1 ? "minute" : "minutes")
    }

    func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(number(value)) \(value == 1 ? singular : plural)"
    }

    func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    private static func seconds(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }

    private static func ranked(_ name: String, _ seconds: Double) -> Ranked? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Ranked(name: trimmed, seconds: Self.seconds(seconds))
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
