import TVCore
import UIKit
import XCTest
@testable import YearExport

final class YearExportArtworkTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testLoaderKeepsServerOrderAndSkipsUnsafeFailedAndUndecodableCovers() async throws {
        let requests = Recorder()
        let artwork = try await YearExportArtworkLoader.load(
            year: 2025, primary: ["red", "../escape", "broken", "missing", "green"], secondary: ["blue", "a/b", "?token=x"],
            owner: "account", currentAccount: { "account" }
        ) { id in
            await requests.add(id)
            switch id {
            case "red": return Self.cover(.red, side: 2000)
            case "green": return Self.cover(.green)
            case "blue": return Self.cover(.blue)
            case "broken": return Data("not an image".utf8)
            default: throw URLError(.fileDoesNotExist)
            }
        }
        let fetched = await requests.values
        XCTAssertEqual(Set(fetched), ["red", "broken", "missing", "green", "blue"])
        XCTAssertEqual(artwork.primary.map(Self.dominant), [.red, .green])
        XCTAssertEqual(artwork.secondary.map(Self.dominant), [.blue])
        XCTAssertLessThanOrEqual(artwork.primary.first?.width ?? .max, YearExportArtworkLoader.maximumPixelSize)
    }

    func testLoaderRequestsNoMoreCoversThanTheServerPublishes() async throws {
        let requests = Recorder()
        let artwork = try await YearExportArtworkLoader.load(
            year: 2025, primary: (0..<8).map { "f\($0)" }, secondary: (0..<30).map { "s\($0)" },
            owner: 1, currentAccount: { 1 }
        ) { id in await requests.add(id); return Self.cover(.red) }
        let fetched = await requests.values
        XCTAssertEqual(fetched.filter { $0.hasPrefix("f") }.count, 5)
        XCTAssertEqual(fetched.filter { $0.hasPrefix("s") }.count, 25)
        XCTAssertEqual(artwork.primary.count, 5)
        XCTAssertEqual(artwork.secondary.count, 25)
    }

    func testCancellingTheLoadStopsFetchingAndYieldsNoArtwork() async throws {
        let requests = Recorder()
        let task = Task {
            try await YearExportArtworkLoader.load(year: 2025, primary: [], secondary: (0..<25).map { "s\($0)" }, owner: 1, currentAccount: { 1 }) { id in
                await requests.add(id)
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return Self.cover(.red)
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while await requests.values.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let began = await requests.values.count
        XCTAssertGreaterThan(began, 0, "the load never started fetching")
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled load must not produce artwork")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        let started = await requests.values.count
        XCTAssertLessThanOrEqual(started, YearExportArtworkLoader.concurrentRequests)
    }

    func testArtworkIsDiscardedWhenTheAccountChangesWhileLoading() async {
        let accounts = Recorder()
        do {
            _ = try await YearExportArtworkLoader.load(year: 2025, primary: ["red"], secondary: [], owner: "alice", currentAccount: {
                await accounts.add("checked")
                return "bob"
            }) { _ in Self.cover(.red) }
            XCTFail("Artwork from another account must not be returned")
        } catch {
            XCTAssertEqual(error as? YearExportArtworkError, .accountChanged)
        }
    }

    func testSnapshotOnlyAcceptsArtworkLoadedForItsOwnYearAndCovers() async throws {
        let stats = try listener(finished: ["red"], listened: ["blue"])
        let matching = try await artwork(year: 2025, primary: ["red"], secondary: ["blue"])
        let otherYear = try await artwork(year: 2024, primary: ["red"], secondary: ["blue"])
        let otherCovers = try await artwork(year: 2025, primary: ["green"], secondary: ["blue"])
        let accepted = try XCTUnwrap(YearExportSnapshot(stats: stats, year: 2025, artwork: matching, locale: locale))
        XCTAssertTrue(accepted.availableLayouts.contains { $0.design == .finishedBooks })
        for rejected in [otherYear, otherCovers] {
            let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats, year: 2025, artwork: rejected, locale: locale))
            XCTAssertFalse(snapshot.availableLayouts.contains { $0.design == .finishedBooks })
            XCTAssertTrue(snapshot.mosaic.isEmpty)
        }
    }

    func testCoverMosaicAndFinishedBooksAreDrawnFromTheSnapshotArtwork() async throws {
        let stats = try listener(finished: ["red"], listened: ["blue"])
        let art = try await artwork(year: 2025, primary: ["red"], secondary: ["blue"])
        let plain = try XCTUnwrap(YearExportSnapshot(stats: stats, year: 2025, locale: locale))
        let covered = try XCTUnwrap(YearExportSnapshot(stats: stats, year: 2025, artwork: art, locale: locale))
        let highlights = YearExportLayout(design: .highlights, shape: .square)!
        XCTAssertNotEqual(YearExportRenderer.render(plain, layout: highlights).pngData, YearExportRenderer.render(covered, layout: highlights).pngData)
        for shape in YearExportDesign.finishedBooks.shapes {
            let artifact = YearExportRenderer.render(covered, layout: YearExportLayout(design: .finishedBooks, shape: shape)!)
            let image = try XCTUnwrap(UIImage(data: artifact.pngData)?.cgImage)
            XCTAssertGreaterThan(Self.ratio(of: .red, in: image), 0.01, "\(shape) did not draw the finished cover")
        }
    }

    func testShareOutputNeverCarriesCoverIdentifiers() async throws {
        let secret = "li_9f2c-cover-id"
        let stats = try listener(finished: [secret], listened: [])
        let art = try await artwork(year: 2025, primary: [secret], secondary: [])
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: stats, year: 2025, artwork: art, locale: locale))
        for layout in snapshot.availableLayouts {
            let artifact = YearExportRenderer.render(snapshot, layout: layout)
            XCTAssertFalse(artifact.shareText.contains(secret))
            XCTAssertFalse(artifact.accessibilityLabel.contains(secret))
            XCTAssertNil(artifact.pngData.range(of: Data(secret.utf8)))
        }
    }

    func testServerSnapshotOffersTheLegacyServerDesigns() async throws {
        let stats = try server()
        let art = try await artwork(year: 2025, primary: [], secondary: ["red", "blue"])
        let snapshot = try XCTUnwrap(YearExportServerSnapshot(stats: stats, year: 2025, artwork: art, locale: locale))
        XCTAssertEqual(Set(snapshot.availableLayouts.map(\.design)), [.serverAdditions, .serverPeople, .serverGenres])
        XCTAssertTrue(snapshot.shareText.contains("2025"))
        XCTAssertTrue(snapshot.shareText.contains("12 books added"))
        XCTAssertTrue(snapshot.shareText.contains("5 authors added"))
        XCTAssertTrue(snapshot.shareText.contains("1 TB"))
        for layout in snapshot.availableLayouts {
            let artifact = YearExportRenderer.render(snapshot, layout: layout)
            XCTAssertTrue(artifact.fileName.hasPrefix("audiobookshelf_server_2025"), artifact.fileName)
            XCTAssertEqual(artifact.snapshotID, snapshot.id)
            let image = try XCTUnwrap(UIImage(data: artifact.pngData)?.cgImage)
            XCTAssertEqual(CGSize(width: image.width, height: image.height), layout.shape.pixelSize)
            XCTAssertGreaterThan(Self.ratio(of: .white, in: image), 0.002, "\(layout)")
        }
        let additions = YearExportRenderer.render(snapshot, layout: YearExportLayout(design: .serverAdditions, shape: .square)!)
        XCTAssertGreaterThan(Self.ratio(of: .red, in: try XCTUnwrap(UIImage(data: additions.pngData)?.cgImage)), 0.01)
    }

    func testServerSnapshotHidesListsItCannotFillAndSurvivesExtremeTotals() throws {
        let stats = try server(authors: [], narrators: [], genres: [], size: 1e300, duration: 1e300)
        let snapshot = try XCTUnwrap(YearExportServerSnapshot(stats: stats, year: 2025, artwork: nil, locale: locale))
        XCTAssertEqual(snapshot.availableLayouts.map(\.design), [.serverAdditions, .serverAdditions])
        for layout in snapshot.availableLayouts { XCTAssertFalse(YearExportRenderer.render(snapshot, layout: layout).pngData.isEmpty) }
        XCTAssertNil(YearExportServerSnapshot(stats: stats, year: 1999, artwork: nil, locale: locale))
    }

    // MARK: Fixtures

    private func artwork(year: Int, primary: [String], secondary: [String]) async throws -> YearExportArtwork {
        try await YearExportArtworkLoader.load(year: year, primary: primary, secondary: secondary, owner: 1, currentAccount: { 1 }) { id in
            Self.cover(id == "blue" ? .blue : id == "green" ? .green : .red)
        }
    }

    private func listener(finished: [String], listened: [String]) throws -> YearListeningStats {
        let json: [String: Any] = [
            "totalListeningSessions": 10, "totalListeningTime": 36_000.0, "totalBookListeningTime": 36_000.0, "totalPodcastListeningTime": 0.0,
            "numBooksFinished": finished.count, "numBooksListened": finished.count + listened.count,
            "topAuthors": [["name": "Writer", "time": 36_000.0]], "topGenres": [["genre": "Fantasy", "time": 36_000.0]],
            "finishedBooksWithCovers": finished, "booksWithCovers": listened
        ]
        return try JSONDecoder().decode(YearListeningStats.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func server(authors: [String] = ["Writer"], narrators: [String] = ["Reader"], genres: [String] = ["Fantasy"], size: Double = 1_099_511_627_776, duration: Double = 8_640_000) throws -> ServerYearStats {
        let json: [String: Any] = [
            "numListeningSessions": 40, "numBooksAdded": 12, "numAuthorsAdded": 5, "totalBooksAddedSize": 5_368_709_120.0,
            "totalBooksAddedDuration": 432_000.0, "booksAddedWithCovers": ["red", "blue"], "totalBooksSize": size,
            "totalBooksDuration": duration, "totalListeningTime": 90_000.0, "numBooks": 800,
            "topAuthors": authors.map { ["name": $0, "time": 9000.0] }, "topNarrators": narrators.map { ["name": $0, "time": 8000.0] },
            "topGenres": genres.map { ["genre": $0, "time": 7000.0] }
        ]
        return try JSONDecoder().decode(ServerYearStats.self, from: JSONSerialization.data(withJSONObject: json))
    }

    enum Tone: Equatable { case red, green, blue, white, other }

    static func cover(_ tone: Tone, side: CGFloat = 300) -> Data {
        let color: UIColor = tone == .red ? .red : tone == .green ? .green : .blue
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side * 1.5), format: format).jpegData(withCompressionQuality: 0.9) { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side * 1.5))
        }
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    static func tone(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Tone {
        if r > 225, g > 225, b > 225 { return .white }
        if r > 200, g < 60, b < 60 { return .red }
        if g > 200, r < 60, b < 60 { return .green }
        if b > 200, r < 60, g < 60 { return .blue }
        return .other
    }

    static func dominant(_ image: CGImage) -> Tone {
        let pixels = pixels(image)
        let middle = (image.height / 2 * image.width + image.width / 2) * 4
        return tone(pixels[middle], pixels[middle + 1], pixels[middle + 2])
    }

    static func ratio(of target: Tone, in image: CGImage) -> Double {
        let pixels = pixels(image)
        var hits = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where tone(pixels[index], pixels[index + 1], pixels[index + 2]) == target { hits += 1 }
        return Double(hits) / Double(image.width * image.height)
    }
}

actor Recorder {
    private(set) var values: [String] = []
    func add(_ value: String) { values.append(value) }
}
