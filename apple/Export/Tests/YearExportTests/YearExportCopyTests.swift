import TVCore
import UIKit
import XCTest
@testable import YearExport

/// Copy arrives as `NativeStrings(language:).copy(YearExportCopy.templates)` plus the language's locale.
final class YearExportCopyTests: XCTestCase {
    /// Marks every template, keeping its placeholders, so any English that bypasses the copy shows up.
    private static let marked = YearExportCopy(
        translations: Dictionary(uniqueKeysWithValues: YearExportCopy.templates.map { ($0, "«\($0)»") }),
        locale: Locale(identifier: "en_US"))

    func testEveryLineOfSharedTextAndEveryComposerLabelComesFromTheCopy() throws {
        XCTAssertGreaterThan(YearExportCopy.templates.count, 40)
        XCTAssertEqual(Set(YearExportCopy.templates).count, YearExportCopy.templates.count, "duplicate templates")
        let listener = try XCTUnwrap(YearExportSnapshot(stats: listenerStats(), year: 2025, copy: Self.marked))
        let server = try XCTUnwrap(YearExportServerSnapshot(stats: serverStats(), year: 2025, artwork: nil, copy: Self.marked))
        let sources: [YearExportSource] = [.listener(listener), .server(server)]
        for source in sources {
            XCTAssertTrue(source.title.hasPrefix("«"), source.title)
            XCTAssertTrue(source.footnote.hasPrefix("«"), source.footnote)
            for layout in source.availableLayouts {
                let artifact = source.render(layout)
                for line in artifact.shareText.split(separator: "\n") { XCTAssertTrue(line.hasPrefix("«"), "untranslated share line: \(line)") }
                XCTAssertTrue(artifact.accessibilityLabel.hasPrefix("«"), artifact.accessibilityLabel)
                XCTAssertTrue(source.copy.title(of: layout.design).hasPrefix("«"))
                XCTAssertTrue(source.copy.summary(of: layout.design).hasPrefix("«"))
                XCTAssertTrue(source.copy.title(of: layout.shape).hasPrefix("«"))
            }
        }
        XCTAssertTrue(YearExportCopy.english.title(of: .highlights) == "Highlights")
    }

    func testTranslatedCopyChangesTheDrawnImage() throws {
        let english = try XCTUnwrap(YearExportSnapshot(stats: listenerStats(), year: 2025))
        let marked = try XCTUnwrap(YearExportSnapshot(stats: listenerStats(), year: 2025, copy: Self.marked))
        for layout in english.availableLayouts {
            XCTAssertNotEqual(YearExportRenderer.render(english, layout: layout).pngData, YearExportRenderer.render(marked, layout: layout).pngData, "\(layout)")
        }
        let server = try XCTUnwrap(YearExportServerSnapshot(stats: serverStats(), year: 2025, artwork: nil))
        let serverMarked = try XCTUnwrap(YearExportServerSnapshot(stats: serverStats(), year: 2025, artwork: nil, copy: Self.marked))
        for layout in server.availableLayouts {
            XCTAssertNotEqual(YearExportRenderer.render(server, layout: layout).pngData, YearExportRenderer.render(serverMarked, layout: layout).pngData, "\(layout)")
        }
    }

    @MainActor func testTheSnapshotKeepsTheLanguageAndLocaleItWasBuiltWith() throws {
        let german = YearExportCopy(translations: ["{0} listening sessions": "{0} Hörsitzungen", "Share {0}": "{0} teilen"], locale: Locale(identifier: "de_DE"))
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: listenerStats(), year: 2025, copy: german))
        let text = snapshot.shareText
        XCTAssertTrue(text.contains("1.234 Hörsitzungen"), text)
        XCTAssertTrue(text.contains("My 2025 in Audiobookshelf"), "untranslated templates stay English: \(text)")
        XCTAssertFalse(text.contains("2.025"), "years are not grouped as numbers")
        let model = YearExportComposerModelProbe.share(.listener(snapshot))
        XCTAssertEqual(model.text, text)
        XCTAssertEqual(model.title, "2025 teilen")
        let server = try XCTUnwrap(YearExportServerSnapshot(stats: serverStats(), year: 2025, artwork: nil, copy: german))
        XCTAssertTrue(server.shareText.contains("1,2 TB"), server.shareText)
    }

    func testTranslationsCannotDropOrInventPlaceholdersAndNamesAreNeverReSubstituted() throws {
        let copy = YearExportCopy(translations: [
            "Top author: {0}": "Autor: {0}",
            "Top narrator: {0}": "Sprecher",                // drops the name: rejected
            "Top genre: {0}": "Genre {0} {1}",               // invents an argument: rejected
            "{0} books finished": "{0} Bücher beendet"
        ], locale: Locale(identifier: "de_DE"))
        let snapshot = try XCTUnwrap(YearExportSnapshot(stats: listenerStats(author: "Writer {0} {1}", narrator: "Reader"), year: 2025, copy: copy))
        let lines = snapshot.shareText.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("Autor: Writer {0} {1}"), "\(lines)")
        XCTAssertTrue(lines.contains("Top narrator: Reader"), "\(lines)")
        XCTAssertTrue(lines.contains("Top genre: Fantasy"), "\(lines)")
        XCTAssertTrue(lines.contains("12 Bücher beendet"), "\(lines)")
    }

    // MARK: Fixtures

    private func listenerStats(author: String = "Writer", narrator: String = "Reader") throws -> YearListeningStats {
        let json: [String: Any] = [
            "totalListeningSessions": 1234, "totalListeningTime": 360_000.0, "totalBookListeningTime": 360_000.0, "totalPodcastListeningTime": 0.0,
            "numBooksFinished": 12, "numBooksListened": 20,
            "topAuthors": [["name": author, "time": 36_000.0]], "topGenres": [["genre": "Fantasy", "time": 36_000.0]],
            "mostListenedNarrator": ["name": narrator, "time": 30_000.0], "mostListenedMonth": ["month": 10, "time": 50_000.0],
            "longestAudiobookFinished": ["id": "li-1", "title": "Long", "duration": 90_000.0, "finishedAt": 1_740_000_000_000.0]
        ]
        return try JSONDecoder().decode(YearListeningStats.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func serverStats() throws -> ServerYearStats {
        let json: [String: Any] = [
            "numListeningSessions": 40, "numBooksAdded": 12, "numAuthorsAdded": 5, "totalBooksAddedSize": 5_368_709_120.0,
            "totalBooksAddedDuration": 432_000.0, "booksAddedWithCovers": [], "totalBooksSize": 1_319_413_953_331.0,
            "totalBooksDuration": 8_640_000.0, "totalListeningTime": 90_000.0, "numBooks": 800,
            "topAuthors": [["name": "Writer", "time": 1.0]], "topNarrators": [["name": "Reader", "time": 1.0]], "topGenres": [["genre": "Fantasy", "time": 1.0]]
        ]
        return try JSONDecoder().decode(ServerYearStats.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// What the composer shares and titles for a source, read through the composer model.
@MainActor enum YearExportComposerModelProbe {
    static func share(_ source: YearExportSource) -> (text: String, title: String) {
        let model = YearExportComposerModel(source: source)
        return (model.artifactForSharing().shareText, source.title)
    }
}
