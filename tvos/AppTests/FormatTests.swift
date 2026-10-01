import XCTest
@testable import AudiobookshelfTV

/// Servers can report any finite Double; formatting must never trap on one.
final class FormatTests: XCTestCase {
    func testClockSaturatesHugeAndInvalidValues() {
        XCTAssertEqual(Format.clock(1e300), Format.clock(Format.longestTime))
        XCTAssertEqual(Format.clock(.greatestFiniteMagnitude), Format.clock(Format.longestTime))
        XCTAssertEqual(Format.clock(.infinity), "0:00")
        XCTAssertEqual(Format.clock(.nan), "0:00")
        XCTAssertEqual(Format.clock(-5), "0:00")
        XCTAssertEqual(Format.clock(3725.9), "1:02:05")
    }

    func testDurationSaturatesHugeValues() {
        XCTAssertEqual(Format.duration(1e300), Format.duration(Format.longestTime))
        XCTAssertEqual(Format.duration(5400, locale: Locale(identifier: "en")), "1 hr, 30 min")
    }

    func testProgressWithHugeServerValuesStillFormats() throws {
        let progress = try JSONDecoder().decode(MediaProgress.self, from: Data(#"{"libraryItemId":"book","currentTime":1e300,"duration":1e300,"progress":1e300,"isFinished":false}"#.utf8))
        let text = try XCTUnwrap(Format.progress(progress, duration: nil))
        XCTAssertTrue(text.hasSuffix("listened"))
        XCTAssertEqual(Format.fraction(progress.progress), 1)
        XCTAssertEqual(Format.fraction(-.infinity), 0)
        XCTAssertEqual(Format.fraction(.nan), 0)
    }

    /// The saved interface language, not the device language, decides how durations and dates read.
    func testDurationsAndDatesFollowTheChosenLanguage() {
        let key = "previewLanguage"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set("de", forKey: key)
        let duration = Format.duration(5400)
        XCTAssertTrue(duration.contains("Std."), duration)
        XCTAssertFalse(duration.contains(" h "), duration)
        let date = Format.published(1_790_812_800_000) ?? ""
        XCTAssertTrue(date.contains("Okt"), date)
    }
}
