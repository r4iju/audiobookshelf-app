import TVCore
import UIKit
import XCTest
@testable import YearExport

final class YearExportTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testEveryLayoutExportsAPNGWithDrawnContentAtItsPixelSize() throws {
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats(), year: 2025, locale: locale))
        XCTAssertEqual(Set(snapshot.availableLayouts.map(\.design)), [.highlights, .topLists, .compact])
        for layout in snapshot.availableLayouts {
            let artifact = YearExportRenderer.render(snapshot, layout: layout)
            let image = try XCTUnwrap(UIImage(data: artifact.pngData)?.cgImage, "\(layout)")
            XCTAssertEqual(CGSize(width: image.width, height: image.height), layout.shape.pixelSize, "\(layout)")
            XCTAssertGreaterThan(brightPixelRatio(image), 0.002, "\(layout) exported without visible text")
        }
    }

    func testRenderedPixelsFollowTheSuppliedStatistics() throws {
        let layout = YearExportLayout(design: .highlights, shape: .square)!
        let first = YearExportRenderer.render(try XCTUnwrap(YearExportSnapshot(stats: stats(finished: 3), year: 2025, locale: locale)), layout: layout)
        let second = YearExportRenderer.render(try XCTUnwrap(YearExportSnapshot(stats: stats(finished: 48), year: 2025, locale: locale)), layout: layout)
        XCTAssertNotEqual(first.pngData, second.pngData)
    }

    func testArtifactIdentityFileNameAndShareTextComeFromItsSnapshot() throws {
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats(finished: 7), year: 2023, locale: locale))
        let artifact = YearExportRenderer.render(snapshot, layout: YearExportLayout(design: .compact, shape: .banner)!)
        XCTAssertEqual(artifact.snapshotID, snapshot.id)
        XCTAssertEqual(artifact.year, 2023)
        XCTAssertEqual(artifact.fileName, "audiobookshelf_my_2023_short.png")
        XCTAssertTrue(artifact.shareText.contains("2023"))
        XCTAssertTrue(artifact.shareText.contains("7 books finished"))
        XCTAssertTrue(artifact.shareText.contains("Brandon Sanderson"))
        XCTAssertFalse(artifact.shareText.contains("2025"))
    }

    func testRejectsYearsTheServerCannotRequest() {
        XCTAssertNil(YearExportSnapshot(stats: stats(), year: 1999, locale: locale))
        XCTAssertNil(YearExportSnapshot(stats: stats(), year: 10_000, locale: locale))
    }

    func testEmptyYearOffersOnlyLayoutsWithContentAndStillRenders() throws {
        let empty = try XCTUnwrap(YearExportSnapshot(stats: stats(finished: 0, listened: 0, sessions: 0, seconds: 0, authors: [], genres: [], narrator: nil, month: nil, longest: nil), year: 2025, locale: locale))
        XCTAssertFalse(empty.availableLayouts.contains { $0.design == .topLists })
        XCTAssertFalse(empty.hasListening)
        for layout in empty.availableLayouts {
            let image = try XCTUnwrap(UIImage(data: YearExportRenderer.render(empty, layout: layout).pngData)?.cgImage)
            XCTAssertGreaterThan(brightPixelRatio(image), 0.002, "\(layout)")
        }
        XCTAssertTrue(empty.shareText.contains("0 books finished"))
    }

    func testRejectsShapesTheDesignDoesNotOffer() {
        XCTAssertNil(YearExportLayout(design: .compact, shape: .portrait))
        XCTAssertNil(YearExportLayout(design: .highlights, shape: .banner))
    }

    @MainActor func testSharingNeverReusesAPreviewForAnotherLayout() async throws {
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats(), year: 2025, locale: locale))
        let model = YearExportComposerModel(snapshot: snapshot)
        await model.refreshPreview()
        XCTAssertEqual(model.preview?.layout, model.layout)
        model.select(design: .compact)
        XCTAssertEqual(model.layout, YearExportLayout(design: .compact, shape: .banner))
        let shared = model.artifactForSharing()
        XCTAssertEqual(shared.layout, model.layout)
        XCTAssertEqual(shared.snapshotID, snapshot.id)
    }

    func testVeryLongNamesRenderWithoutEscapingTheCanvas() throws {
        let long = String(repeating: "Extraordinarily Long Narrator Name ", count: 40)
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats(authors: [long, long, long, long, long], genres: [long], narrator: long), year: 2025, locale: locale))
        for layout in snapshot.availableLayouts {
            let image = try XCTUnwrap(UIImage(data: YearExportRenderer.render(snapshot, layout: layout).pngData)?.cgImage)
            XCTAssertLessThan(brightPixelRatio(image), 0.25, "\(layout) overflowed with text")
        }
    }

    private func stats(
        finished: Int = 12, listened: Int = 19, sessions: Int = 240, seconds: Double = 512_400,
        authors: [String] = ["Brandon Sanderson", "Ursula K. Le Guin", "Terry Pratchett"],
        genres: [String] = ["Fantasy", "Science Fiction"],
        narrator: String? = "Kate Reading", month: Int? = 10, longest: String? = "The Way of Kings"
    ) -> YearListeningStats {
        var json: [String: Any] = [
            "totalListeningSessions": sessions, "totalListeningTime": seconds,
            "totalBookListeningTime": seconds * 0.8, "totalPodcastListeningTime": seconds * 0.2,
            "numBooksFinished": finished, "numBooksListened": listened,
            "topAuthors": authors.enumerated().map { ["name": $1, "time": Double(10_000 - $0 * 1000)] },
            "topGenres": genres.enumerated().map { ["genre": $1, "time": Double(9_000 - $0 * 1000)] }
        ]
        if let narrator { json["mostListenedNarrator"] = ["name": narrator, "time": 40_000] }
        if let month { json["mostListenedMonth"] = ["month": month, "time": 80_000] }
        if let longest { json["longestAudiobookFinished"] = ["title": longest, "duration": 160_000] }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(YearListeningStats.self, from: data)
    }

    private func brightPixelRatio(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var bright = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] > 225 && pixels[index + 1] > 225 && pixels[index + 2] > 225 {
            bright += 1
        }
        return Double(bright) / Double(width * height)
    }
}
