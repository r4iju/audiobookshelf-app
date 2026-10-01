import XCTest

/// Drives the installed legacy app (`run.sh` seeds its synthetic library first): opens the
/// downloaded EPUB in the app's reader so it writes its own reader storage, exports from Settings,
/// saves the package to On My iPhone through the Files save dialog, then removes the export.
final class LegacyExportJourneyUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.audiobookshelf.app.dev")

    override func setUp() {
        continueAfterFailure = false
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func text(beginningWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let ready = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: element)
        wait(for: [ready], timeout: timeout)
        element.tap()
    }

    /// The reader hides its toolbar until the page is tapped.
    private func revealReaderToolbar(_ control: XCUIElement) {
        if !control.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        tapWhenReady(control)
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testExportFromSettingsAndSaveToOnMyIPhone() throws {
        app.launch()
        tapWhenReady(app.staticTexts["Synthetic Book"].firstMatch)
        tapWhenReady(app.buttons["auto_stories"].firstMatch)
        sleep(3)
        revealReaderToolbar(button("settings"))
        tapWhenReady(button("Serif"))
        tapWhenReady(button("close"))
        // epub.js computes and stores the book's locations after it opens.
        sleep(10)
        revealReaderToolbar(button("chevron_left"))

        tapWhenReady(button("Toggle side drawer"))
        let settingsLink = app.links["settings Settings"].firstMatch
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        sleep(1)
        // The drawer's overlay keeps its links from counting as hittable; tap where the link is.
        settingsLink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let export = button("Export for the new app")
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        for _ in 0..<6 where !export.isHittable { app.swipeUp() }
        export.tap()

        let save = button("Save to Files")
        XCTAssertTrue(save.waitForExistence(timeout: 60), "the export finished")
        XCTAssertTrue(text(beginningWith: "Audiobookshelf Export ").exists)
        attachScreenshot("export-ready")
        save.tap()

        let pickerSave = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 15), "the Files save dialog opened")
        XCTAssertFalse(text(beginningWith: "The save dialog could not be shown").exists,
                       "an open save dialog is not reported as failed")

        // Swiping the dialog away resolves the save, so it can be opened again.
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(pickerSave.waitForNonExistence(timeout: 10), "the save dialog was dismissed")
        tapWhenReady(save)
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 15), "the save dialog opens again after a dismissal")
        XCTAssertFalse(text(beginningWith: "The export is busy").exists)
        let location = app.staticTexts["On My iPhone"].firstMatch
        if !location.exists {
            tapWhenReady(app.buttons["BackButton"])
            tapWhenReady(app.staticTexts["On My iPhone"].firstMatch)
        }
        attachScreenshot("save-dialog")
        tapWhenReady(pickerSave)

        XCTAssertTrue(text(beginningWith: "Saved.").waitForExistence(timeout: 30), "the app reports the package saved")
        attachScreenshot("saved")
        tapWhenReady(button("Remove export"))
        XCTAssertTrue(button("Export for the new app").waitForExistence(timeout: 10), "the export was removed")
    }
}
