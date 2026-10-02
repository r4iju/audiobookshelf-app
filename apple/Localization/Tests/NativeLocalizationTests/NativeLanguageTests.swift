import XCTest
@testable import NativeLocalization

final class NativeLanguageTests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func testEveryLegacySelectableLanguageRemainsSelectableInLegacyOrder() throws {
        let source = try String(contentsOf: Self.repository.appendingPathComponent("plugins/i18n.js"))
        let map = try XCTUnwrap(source.range(of: "const languageCodeMap = {").map { source[$0.upperBound...] })
        let body = map[..<(try XCTUnwrap(map.range(of: "\n}")).lowerBound)]
        let entries = body.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ": { label: '")
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "'")), String(parts[1].prefix { $0 != "'" }))
        }
        XCTAssertEqual(entries.count, 30)
        XCTAssertEqual(NativeLanguage.all.map(\.code), entries.map(\.0))
        XCTAssertEqual(NativeLanguage.all.map(\.name), entries.map(\.1))
    }

    func testSavedLegacyChoiceWinsOverDeviceLanguage() {
        XCTAssertEqual(NativeLanguage.resolve(saved: "de", preferred: ["fr-FR", "en-US"]).code, "de")
        XCTAssertEqual(NativeLanguage.resolve(saved: "en-us", preferred: ["fr-FR"]).code, "en-us")
    }

    func testUnknownSavedChoiceFollowsTheDevice() {
        XCTAssertEqual(NativeLanguage.resolve(saved: "xx", preferred: ["fr-CA"]).code, "fr")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["sv-SE"]).code, "sv")
    }

    func testDeviceLanguagesMatchLegacyRegionalAndScriptVariants() {
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["pt-PT"]).code, "pt-br")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["zh-Hans-CN"]).code, "zh-cn")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["nb-NO"]).code, "no")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["en-GB"]).code, "en-us")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["vi-VN"]).code, "vi-vn")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["he-IL"]).code, "he")
    }

    func testUnsupportedDeviceLanguagesAreSkippedBeforeTheEnglishDefault() {
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["zh-Hant-TW", "ja-JP", "de-AT"]).code, "de")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: ["ja-JP", "fa-IR"]).code, "en-us")
        XCTAssertEqual(NativeLanguage.resolve(saved: nil, preferred: []).code, "en-us")
    }

    func testArabicAndHebrewUseRightToLeftLayout() {
        XCTAssertEqual(NativeLanguage.all.filter(\.isRightToLeft).map(\.code), ["ar", "he"])
    }

    /// Migration hands over the legacy `deviceSettings.languageCode`. Only an explicit legacy choice is kept; the legacy
    /// default and unknown codes leave the device language in charge, and a choice made in the native app is never replaced.
    func testMigratedLegacyLanguageIsAdoptedOnlyWhenTheNativeAppHasNone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        XCTAssertFalse(NativeLanguage.adoptLegacy("xx", defaults: defaults))
        XCTAssertFalse(NativeLanguage.adoptLegacy(nil, defaults: defaults))
        XCTAssertNil(defaults.string(forKey: NativeStrings.savedKey))
        // The legacy app showed English for `en-us` whatever the device language, so it carries over like any other code.
        XCTAssertTrue(NativeLanguage.adoptLegacy("en-us", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: NativeStrings.savedKey), "en-us")
        XCTAssertFalse(NativeLanguage.adoptLegacy("de", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: NativeStrings.savedKey), "en-us")
        defaults.removePersistentDomain(forName: #function)
        XCTAssertTrue(NativeLanguage.adoptLegacy("pt-br", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: NativeStrings.savedKey), "pt-br")
        defaults.removePersistentDomain(forName: #function)
    }
}
