import XCTest
@testable import NativeLocalization

final class NativeStringsTests: XCTestCase {
    private static let localization = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let repository = localization.deletingLastPathComponent().deletingLastPathComponent()

    private func strings(_ code: String) -> NativeStrings {
        NativeStrings(language: NativeLanguage.all.first { $0.code == code }!, bundle: .module)
    }

    func testUntranslatedNativeLabelsUseEnglishWithoutLegacyTables() {
        XCTAssertEqual(strings("de")("Settings"), "Settings")
        XCTAssertEqual(strings("fr")("Continue listening"), "Continue listening")
        XCTAssertEqual(strings("ar")("Haptic feedback"), "Haptic feedback")
    }

    func testEnglishContextsKeepTheirNativeMeanings() {
        XCTAssertEqual(strings("en-us")("Light", context: .theme), "Light")
        XCTAssertEqual(strings("en-us")("Light", context: .hapticStrength), "Light")
    }

    func testEnglishKeepsTheNativeWording() {
        XCTAssertEqual(strings("en-us")("Continue listening"), "Continue listening")
    }

    func testTextWithoutATranslationFallsBackToEnglish() {
        XCTAssertEqual(strings("de")("Not a native text"), "Not a native text")
    }

    /// Renderers outside the app, such as the year export, receive an immutable copy of only the translated texts, so
    /// anything untranslated keeps their own English default and nothing reads app resources while drawing.
    func testCopyForAnotherRendererCarriesOnlyTranslatedText() {
        XCTAssertEqual(strings("de").copy(["Settings", "Not a native text"]), [:])
        XCTAssertEqual(strings("en-us").copy(["Settings"]), [:])
    }

    /// The Language screen shows each language's share in whole percent. A language missing any text must not read 100%,
    /// and one with every text translated reads 100%.
    func testTranslatedPercentNeverRoundsAPartialLanguageUpToComplete() {
        XCTAssertEqual(NativeStrings.translatedPercent(translated: 698, of: 699), 99)
        XCTAssertEqual(NativeStrings.translatedPercent(translated: 699, of: 699), 100)
        XCTAssertEqual(NativeStrings.translatedPercent(translated: 171, of: 678), 25)
        XCTAssertEqual(NativeStrings.translatedPercent(translated: 0, of: 0), 0)
    }

    func testPlaceholdersAreSubstitutedInOrder() {
        XCTAssertEqual(strings("en-us")("File {0} of {1}", 1, 2), "File 1 of 2")
    }

    func testShippedTranslationsAreMaintainedHereOrUseEnglish() throws {
        let keys = try XCTUnwrap(NSDictionary(contentsOf: try XCTUnwrap(Bundle.module.url(forResource: NativeStrings.tableName, withExtension: "strings", subdirectory: nil, localization: "en"))) as? [String: String]).keys
        for language in NativeLanguage.all where language.code != "en-us" {
            let file = Self.localization.appendingPathComponent("translations/\(language.code).json")
            let maintained = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
            let native = strings(language.code)
            for key in keys {
                let parts = key.components(separatedBy: "::")
                let shown = parts.count == 2 ? native(parts[1], context: try XCTUnwrap(NativeTextContext(rawValue: parts[0]))) : native(key)
                XCTAssertEqual(shown, maintained[key] ?? parts.last!, "\(language.code): \(key)")
            }
        }
    }
}
