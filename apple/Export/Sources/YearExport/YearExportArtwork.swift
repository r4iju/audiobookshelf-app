#if canImport(TVCore)
import TVCore
#endif
import CoreGraphics
import Foundation
import ImageIO

public enum YearExportArtworkError: Error, Equatable {
    /// The signed-in account changed while covers were loading, so they were discarded.
    case accountChanged
}

/// Decoded cover pixels for one account and year, keyed to the exact cover lists the stats
/// published. It holds no identifiers that reach an export: only the requested lists are kept,
/// to let a snapshot reject artwork loaded for other stats.
public struct YearExportArtwork: @unchecked Sendable {
    public let year: Int
    let primaryIDs: [String]
    let secondaryIDs: [String]
    let primary: [CGImage]
    let secondary: [CGImage]

    func matches(year: Int, primary: [String], secondary: [String]) -> Bool {
        self.year == year
            && primaryIDs == Array(primary.prefix(YearExportArtworkLoader.primaryLimit))
            && secondaryIDs == Array(secondary.prefix(YearExportArtworkLoader.secondaryLimit))
    }
}

/// Loads the covers named by a year's stats. `fetch` is the app's authenticated cover request
/// (for example `APIClient.coverData(itemID:)`), so tokens stay in request headers and never
/// enter the artwork, the image or the share text.
public enum YearExportArtworkLoader {
    public static let maximumPixelSize = 512
    public static let concurrentRequests = 4
    /// Matches the server: five finished (or added) covers and up to 25 others.
    static let primaryLimit = 5
    static let secondaryLimit = 25
    static let maximumBytes = 20 * 1024 * 1024

    /// Loads covers in server order, skipping unsafe identifiers and covers that fail to
    /// download or decode. Throws `CancellationError` when cancelled. `currentAccount()` is checked
    /// before and after every fetch, including failed ones; the first time it is not `owner`, or a
    /// fetch throws `accountChanged`, the whole load stops with `YearExportArtworkError.accountChanged`.
    /// Use an owner that changes on every sign-in (see `load(year:primary:secondary:api:authorization:)`),
    /// so signing out and back in (A, B, A) also counts as a change.
    public static func load<Account: Equatable & Sendable>(
        year: Int, primary: [String], secondary: [String], owner: Account,
        currentAccount: @escaping @Sendable () async throws -> Account,
        fetch: @escaping @Sendable (String) async throws -> Data
    ) async throws -> YearExportArtwork {
        @Sendable func requireOwner() async throws {
            guard try await currentAccount() == owner else { throw YearExportArtworkError.accountChanged }
        }
        let primaryIDs = Array(primary.prefix(primaryLimit))
        let secondaryIDs = Array(secondary.prefix(secondaryLimit))
        let jobs = primaryIDs.enumerated().map { (list: 0, index: $0.offset, id: $0.element) }
            + secondaryIDs.enumerated().map { (list: 1, index: $0.offset, id: $0.element) }
        var pending = jobs.filter { isSafe($0.id) }.makeIterator()
        var images: [[Int: CGImage]] = [[:], [:]]

        try await withThrowingTaskGroup(of: (list: Int, index: Int, image: CGImage?).self) { group in
            func enqueue() -> Bool {
                guard !Task.isCancelled, let job = pending.next() else { return false }
                group.addTask {
                    try await requireOwner()
                    do {
                        let data = try await fetch(job.id)
                        try await requireOwner()
                        try Task.checkCancellation()
                        return (job.list, job.index, decode(data))
                    } catch {
                        // A failure caused by an account change must end the load, not read as a missing cover.
                        if error as? YearExportArtworkError == .accountChanged { throw error }
                        try await requireOwner()
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        return (job.list, job.index, nil)
                    }
                }
                return true
            }
            for _ in 0..<concurrentRequests where !enqueue() { break }
            while let result = try await group.next() {
                if let image = result.image { images[result.list][result.index] = image }
                _ = enqueue()
            }
        }
        try Task.checkCancellation()
        try await requireOwner()
        try Task.checkCancellation()
        return YearExportArtwork(
            year: year, primaryIDs: primaryIDs, secondaryIDs: secondaryIDs,
            primary: images[0].sorted { $0.key < $1.key }.map(\.value),
            secondary: images[1].sorted { $0.key < $1.key }.map(\.value)
        )
    }

    /// Library item IDs become one path segment of `api/items/<id>/cover`; anything that could
    /// leave that segment or add a query is refused before a request is made.
    static func isSafe(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128, id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar))
        }
    }

    /// Downsamples through ImageIO so a large cover never decodes at full size.
    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// An immutable copy of the server-wide year (`GET /api/stats/year/:year`, admin and root only).
/// Build it only from a response the signed-in admin received; non-admin accounts never see it.
public struct YearExportServerSnapshot: Identifiable, Sendable {
    public let id = UUID()
    public let year: Int
    public let booksAdded: Int
    public let authorsAdded: Int
    public let sessions: Int
    public let libraryBooks: Int
    public let collectionBytes: Double
    public let addedBytes: Double
    public let collectionSeconds: Double
    public let addedSeconds: Double
    public let listeningSeconds: Double
    public let topAuthors: [YearExportSnapshot.Ranked]
    public let topNarrators: [YearExportSnapshot.Ranked]
    public let topGenres: [YearExportSnapshot.Ranked]
    let artwork: YearExportArtwork?
    let format: YearExportFormat

    /// `artwork` is used only when it was loaded for this year's `booksAddedWithCovers`
    /// (passed as the loader's `secondary` list).
    /// English text with the given locale's numbers and durations.
    public init?(stats: ServerYearStats, year: Int, artwork: YearExportArtwork?, locale: Locale) {
        self.init(stats: stats, year: year, artwork: artwork, copy: YearExportCopy(locale: locale))
    }

    /// `copy` is kept with the snapshot, so its images and text stay in that language. English by default.
    public init?(stats: ServerYearStats, year: Int, artwork: YearExportArtwork?, copy: YearExportCopy = .english) {
        guard (2000...9999).contains(year) else { return nil }
        self.year = year
        format = YearExportFormat(copy: copy)
        booksAdded = max(stats.numBooksAdded, 0)
        authorsAdded = max(stats.numAuthorsAdded, 0)
        sessions = max(stats.numListeningSessions, 0)
        libraryBooks = max(stats.numBooks, 0)
        collectionBytes = YearExportFormat.clean(stats.totalBooksSize)
        addedBytes = YearExportFormat.clean(stats.totalBooksAddedSize)
        collectionSeconds = YearExportFormat.clean(stats.totalBooksDuration)
        addedSeconds = YearExportFormat.clean(stats.totalBooksAddedDuration)
        listeningSeconds = YearExportFormat.clean(stats.totalListeningTime)
        topAuthors = Array(stats.topAuthors.compactMap { YearExportFormat.ranked($0.name, $0.time) }.prefix(5))
        topNarrators = Array(stats.topNarrators.compactMap { YearExportFormat.ranked($0.name, $0.time) }.prefix(5))
        topGenres = Array(stats.topGenres.compactMap { YearExportFormat.ranked($0.genre, $0.time) }.prefix(5))
        self.artwork = artwork.flatMap { $0.matches(year: year, primary: [], secondary: stats.booksAddedWithCovers) ? $0 : nil }
    }

    var covers: [CGImage] { artwork?.secondary ?? [] }

    public var availableLayouts: [YearExportLayout] {
        [YearExportDesign.serverAdditions, .serverPeople, .serverGenres]
            .filter { design in
                switch design {
                case .serverPeople: return !topAuthors.isEmpty || !topNarrators.isEmpty
                case .serverGenres: return !topGenres.isEmpty
                default: return true
                }
            }
            .flatMap { design in design.shapes.compactMap { YearExportLayout(design: design, shape: $0) } }
    }

    var copy: YearExportCopy { format.copy }
    func number(_ value: Int) -> String { format.number(Double(value)) }

    public var shareText: String {
        var lines = [
            copy("Audiobookshelf server {0} in review", String(year)),
            booksAdded == 1 ? copy("{0} book added", number(booksAdded)) : copy("{0} books added", number(booksAdded)),
            authorsAdded == 1 ? copy("{0} author added", number(authorsAdded)) : copy("{0} authors added", number(authorsAdded)),
            sessions == 1 ? copy("{0} listening session", number(sessions)) : copy("{0} listening sessions", number(sessions))
        ]
        if collectionBytes > 0 { lines.append(copy("Collection: {0} (+{1} this year)", format.bytes(collectionBytes), format.bytes(addedBytes))) }
        if collectionSeconds > 0 {
            lines.append(copy("Total duration: {0} (+{1} this year)", format.longDuration(collectionSeconds), format.longDuration(addedSeconds)))
        }
        if let author = topAuthors.first { lines.append(copy("Top author: {0}", author.name)) }
        return lines.joined(separator: "\n")
    }
}

public extension YearExportArtworkLoader {
    /// Loads covers for the sign-in identified by `authorization`, the `api.authorizationRevision` read when
    /// the stats were requested. Every request is pinned to it, so none is ever sent with a later session,
    /// and any sign-in change (even back to the same account) aborts with `accountChanged`.
    @MainActor static func load(year: Int, primary: [String], secondary: [String], api: APIClient, authorization: UUID) async throws -> YearExportArtwork {
        try await load(year: year, primary: primary, secondary: secondary, owner: authorization,
                       currentAccount: { await api.authorizationRevision },
                       fetch: { try await api.coverData(itemID: $0, authorization: authorization) })
    }
}
