import XCTest

/// The shared core describes its failures in English for its own tests and logs. With the app's tables installed, the same
/// failures read in the chosen language wherever the app shows them, such as a rejected sign-in.
final class CoreTextTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        saved = UserDefaults.standard.string(forKey: NativeStrings.savedKey)
        NativeStrings.installCoreText(bundle: Bundle(for: Self.self))
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: NativeStrings.savedKey) } else { UserDefaults.standard.removeObject(forKey: NativeStrings.savedKey) }
        CoreText.lookup = CoreText.english
    }

    private func strings(_ code: String) -> NativeStrings {
        NativeStrings(language: NativeLanguage.named(code)!, bundle: Bundle(for: Self.self))
    }

    func testSharedCoreFailuresReadInTheChosenLanguage() {
        UserDefaults.standard.set("de", forKey: NativeStrings.savedKey)
        let rejected = strings("de")("The username or password was not accepted.")
        XCTAssertNotEqual(rejected, "The username or password was not accepted.", "German must translate the rejected sign-in")
        XCTAssertEqual(APIError.http(401).localizedDescription, rejected)
        XCTAssertEqual(APIError.http(503).localizedDescription, strings("de")("The server returned HTTP {0}. Please try again.", 503))
        XCTAssertNotEqual(APIError.http(503).localizedDescription, "The server returned HTTP 503. Please try again.")
    }

    func testEnglishKeepsTheSharedCoreWording() {
        UserDefaults.standard.set("en-us", forKey: NativeStrings.savedKey)
        XCTAssertEqual(APIError.http(401).localizedDescription, "The username or password was not accepted.")
        XCTAssertEqual(APIError.http(503).localizedDescription, "The server returned HTTP 503. Please try again.")
    }
}
