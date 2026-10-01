import XCTest
@testable import NativeLocalization

final class NativeStringsTests: XCTestCase {
    private static let localization = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let repository = localization.deletingLastPathComponent().deletingLastPathComponent()

    private func strings(_ code: String) -> NativeStrings {
        NativeStrings(language: NativeLanguage.all.first { $0.code == code }!, bundle: .module)
    }

    func testEquivalentNativeTextShowsTheLegacyTranslation() {
        XCTAssertEqual(strings("de")("Settings"), "Einstellungen")
        XCTAssertEqual(strings("fr")("Continue listening"), "Continuer l'écoute")
        XCTAssertEqual(strings("ar")("Haptic feedback"), "ردود الفعل اللمسية")
    }

    func testEnglishKeepsTheNativeWording() {
        XCTAssertEqual(strings("en-us")("Continue listening"), "Continue listening")
    }

    func testTextWithoutALegacyEquivalentFallsBackToEnglish() {
        XCTAssertEqual(strings("de")("Network preferences"), "Network preferences")
    }

    /// Renderers outside the app, such as the year export, receive an immutable copy of only the translated texts, so
    /// anything untranslated keeps their own English default and nothing reads app resources while drawing.
    func testCopyForAnotherRendererCarriesOnlyTranslatedText() {
        XCTAssertEqual(strings("de").copy(["Settings", "Network preferences", "Not a native text"]), ["Settings": "Einstellungen"])
        XCTAssertEqual(strings("en-us").copy(["Settings"]), [:])
    }

    func testPlaceholdersAreSubstitutedInOrder() {
        XCTAssertEqual(strings("en-us")("File {0} of {1}", 1, 2), "File 1 of 2")
    }

    /// Every shipped translation must be the real legacy value for its mapped key, and anything the legacy app
    /// left untranslated, empty, marked up, or with different placeholders must fall back to English.
    func testShippedTranslationsAreExactlyTheUsableLegacyTranslations() throws {
        let mapping = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.localization.appendingPathComponent("legacy-equivalents.json")))
        XCTAssertFalse(mapping.isEmpty)
        for language in NativeLanguage.all where language.code != "en-us" {
            let legacy = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.repository.appendingPathComponent("strings/\(language.code).json")))
            let native = strings(language.code)
            for (english, key) in mapping {
                let candidate = legacy[key] ?? ""
                let usable = !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !candidate.contains("<")
                    && NativeStrings.placeholders(in: candidate) == NativeStrings.placeholders(in: english)
                XCTAssertEqual(native(english), usable ? candidate : english, "\(language.code): \(english)")
            }
        }
    }
}
