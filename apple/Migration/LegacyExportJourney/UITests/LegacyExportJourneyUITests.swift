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
    /// On iOS 26 the save dialog can leave the settings page scrolled.
    private func scrollToAndTap(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        tapWhenReady(element)
    }

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

        // Identified on iOS 27, only labelled on iOS 26.
        let pickerSave = app.buttons.matching(NSPredicate(format: "identifier == 'DOCPicker.actionButton' OR label == 'Save'")).firstMatch
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 15), "the Files save dialog opened")
        XCTAssertFalse(text(beginningWith: "The save dialog could not be shown").exists,
                       "an open save dialog is not reported as failed")

        // Past the plugin's presentation check, only the dialog can end the save: swiping it away
        // must release the save as not saved, so it can be opened again.
        sleep(7)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(pickerSave.waitForNonExistence(timeout: 10), "the save dialog was swiped away")
        sleep(1)
        XCTAssertFalse(text(beginningWith: "Saved.").exists, "a dismissed save is not reported as saved")
        XCTAssertFalse(text(beginningWith: "The save dialog could not be shown").exists)
        scrollToAndTap(save)
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 15), "the save dialog opens again after a dismissal")
        XCTAssertFalse(text(beginningWith: "The export is busy").exists, "the swiped-away save was released")

        // Cancel, at the top of the dialog, releases it the same way.
        let cancel = app.buttons["Cancel"].firstMatch
        if !cancel.exists { tapWhenReady(app.buttons["BackButton"]) }
        tapWhenReady(cancel)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "Cancel dismissed the save dialog")
        sleep(1)
        XCTAssertFalse(text(beginningWith: "Saved.").exists, "a cancelled save is not reported as saved")
        scrollToAndTap(save)
        XCTAssertTrue(pickerSave.waitForExistence(timeout: 15), "the save dialog opens again after Cancel")
        XCTAssertFalse(text(beginningWith: "The export is busy").exists, "the cancelled save was released")
        let location = app.staticTexts["On My iPhone"].firstMatch
        if !location.exists {
            tapWhenReady(app.buttons["BackButton"])
            tapWhenReady(app.staticTexts["On My iPhone"].firstMatch)
        }
        attachScreenshot("save-dialog")
        tapWhenReady(pickerSave)

        XCTAssertTrue(text(beginningWith: "Saved.").waitForExistence(timeout: 30), "the app reports the package saved")
        attachScreenshot("saved")
        scrollToAndTap(button("Remove export"))
        XCTAssertTrue(button("Export for the new app").waitForExistence(timeout: 10), "the export was removed")
    }
}
