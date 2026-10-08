import XCTest
import UIKit

@MainActor final class LargestDownloads239Journey: NativeJourney {
    func testLargestDownloadLabelsFitAndRetryPlayRemoveStayIndependent() async throws {
        try await FixtureControl.configure("download-partial-ebook")
        connectSelectAndRestore(serverURL: "http://127.0.0.1:19765/abs", verifyRestoration: false)
        let app = XCUIApplication()
        app.buttons["book-book-0"].tap()
        let download = app.buttons["Download for offline"]
        for _ in 0..<8 where !(download.exists && download.isHittable) { app.swipeUp() }
        XCTAssertTrue(download.waitForExistence(timeout: 5)); download.tap()
        app.navigationBars.buttons["BackButton"].tap()
        mainDestination("Downloads", in: app).tap()
        let retry = app.buttons["Retry download"]
        XCTAssertTrue(retry.waitForExistence(timeout: 45))
        guard retry.exists else { return }
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        for title in ["Retry download", "Remove download"] {
            let button = app.buttons[title]
            for _ in 0..<8 where !(button.exists && button.isHittable) { app.swipeUp() }
            XCTAssertTrue(button.exists); XCTAssertTrue(button.isHittable)
            let text = button.staticTexts[title].firstMatch
            let frame = text.exists ? text.frame : button.frame
            let fitted = (title as NSString).boundingRect(with: CGSize(width: frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            print("ACTUAL-DOWNLOAD-LABEL \(title) text=\(frame) button=\(button.frame) bodyFont=\(font.pointSize) requiredHeight=\(ceil(fitted.height))")
            let longestWord = title.split(separator: " ").map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            print("ACTUAL-DOWNLOAD-WORD \(title) requiredWidth=\(longestWord) available=\(frame.width)")
            XCTAssertGreaterThanOrEqual(frame.width + 2, longestWord, "Essential action words must fit without clipping or ellipsis")
            XCTAssertGreaterThanOrEqual(frame.height + 2, ceil(fitted.height), "Full native action text must fit at the actual largest text size")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        XCTAssertFalse(app.buttons["offline-book-0"].exists)
        try await FixtureControl.configure("baseline")
        retry.tap()
        let saved = app.buttons["offline-book-0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 45)); saved.tap()
        let play = app.buttons["Play offline"]
        for _ in 0..<8 where !(play.exists && play.isHittable) { app.swipeUp() }
        XCTAssertTrue(play.exists); play.tap()
        XCTAssertTrue(app.buttons["mini-pause-playback"].waitForExistence(timeout: 10))
        let remove = app.buttons["Remove download"]
        for _ in 0..<8 where !(remove.exists && remove.isHittable) { app.swipeUp() }
        XCTAssertTrue(remove.exists); remove.tap()
        for _ in 0..<8 where !app.staticTexts["No downloads yet"].exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["No downloads yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["offline-book-0"].exists)
        XCTAssertFalse(app.buttons["Retry download"].exists)
    }
}
