import XCTest
@testable import NativeDiagnostics

final class DiagnosticRedactorTests: XCTestCase {
    func testAddressesKeepTheirServerButLoseCredentialsQueriesAndFragments() {
        let text = DiagnosticRedactor.redact("GET https://reader:hunter2@books.example.lan:13378/abs/api/items/li_1/play?token=s3cr3t&lang=de#access_token=frag failed")
        XCTAssertTrue(text.contains("https://books.example.lan:13378/abs/api/items/li_1/play"), text)
        for secret in ["reader", "hunter2", "s3cr3t", "frag"] { XCTAssertFalse(text.contains(secret), text) }
        XCTAssertTrue(text.hasSuffix(" failed"), text)
    }

    func testAuthorizationValuesAndSessionTokensAreRemovedFromFreeText() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJ1c2VySWQiOiJxYSJ9.c2lnbmF0dXJl"
        let text = DiagnosticRedactor.redact("""
        Authorization: Bearer abc.def-123
        {"accessToken":"\(jwt)","refreshToken": "rt-998877", "username":"qa"}
        password=pw-secret-77 x-refresh-token: rt-445566 seen \(jwt)
        """)
        for secret in ["abc.def-123", "rt-998877", "pw-secret-77", "rt-445566", "eyJ"] { XCTAssertFalse(text.contains(secret), text) }
        XCTAssertTrue(text.contains("\"username\":\"qa\""), text)
    }

    func testOrdinaryFailureWordsRemainReadable() {
        let message = "Token refresh failed with error code -1004; password field was empty."
        XCTAssertEqual(DiagnosticRedactor.redact(message), message)
    }

    func testMaskingAddressesHidesTheServerLikeTheLegacyLogScreen() {
        let text = DiagnosticRedactor.redact("Could not reach http://10.0.0.5:13378/abs/login", maskingAddresses: true)
        XCTAssertFalse(text.contains("10.0.0.5"), text)
        XCTAssertTrue(text.contains("http://[server]/abs/login"), text)
    }

    func testErrorsAreDescribedByDomainCodeAndRedactedAddress() {
        let failure = URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "http://qa:pw@127.0.0.1:25799/abs/login?token=leak")!])
        let description = DiagnosticRedactor.describe(failure)
        XCTAssertTrue(description.contains("NSURLErrorDomain -1004"), description)
        XCTAssertTrue(description.contains("http://127.0.0.1:25799/abs/login"), description)
        XCTAssertFalse(description.contains("pw"), description)
        XCTAssertFalse(description.contains("leak"), description)
    }

    func testCookieHeadersLoseEveryCookie() {
        let text = DiagnosticRedactor.redact("""
        Cookie: absAccessToken=synthetic-a; absRefreshToken=synthetic-b
        set-cookie: session=synthetic-s; Path=/; HttpOnly
        status 401
        """)
        for secret in ["synthetic-a", "synthetic-b", "synthetic-s"] { XCTAssertFalse(text.contains(secret), text) }
        XCTAssertTrue(text.hasSuffix("status 401"), text)
    }

    func testWrappedSingleQuotedAndPrefixedCredentialValuesAreRemoved() {
        let text = DiagnosticRedactor.redact("""
        refreshToken: Optional("synthetic-c") password='synthetic-d' token = 'synthetic-e'
        absRefreshToken=synthetic-f {"absAccessToken":"synthetic-g"} user: Optional("qa")
        """)
        for secret in ["synthetic-c", "synthetic-d", "synthetic-e", "synthetic-f", "synthetic-g"] { XCTAssertFalse(text.contains(secret), text) }
        XCTAssertTrue(text.contains("user: Optional(\"qa\")"), text)
    }

    func testSwiftErrorPayloadsAreNotCopiedIntoDiagnostics() {
        enum Failure: Error { case rejected(String) }
        let description = DiagnosticRedactor.describe(Failure.rejected("synthetic-payload-h"))
        XCTAssertTrue(description.contains("rejected"), description)
        XCTAssertFalse(description.contains("synthetic-payload-h"), description)
    }

    func testEventMessagesAndDetailsAreBothMaskedForDisplay() {
        let event = DiagnosticEvent(category: .reading, message: "Could not save to http://10.0.0.5:13378/abs/api/me", detail: "at https://10.0.0.5/abs", date: Date())
        let shown = event.presented(maskingAddresses: true)
        XCTAssertFalse(shown.message.contains("10.0.0.5"), shown.message)
        XCTAssertFalse(shown.detail?.contains("10.0.0.5") ?? true, shown.detail ?? "")
        XCTAssertTrue(event.presented(maskingAddresses: false).message.contains("10.0.0.5:13378"))
    }

    func testEscapedQuotesDoNotEndACredentialValueEarly() {
        let text = DiagnosticRedactor.redact(#"""
        {"password":"synthetic-start\"synthetic-tail"}
        token='synthetic-one\'synthetic-two' refreshToken: Optional("synthetic-three\"synthetic-four")
        {"secret":"synthetic-five\\","user":"qa"}
        """#)
        for secret in ["synthetic-start", "synthetic-tail", "synthetic-one", "synthetic-two", "synthetic-three", "synthetic-four", "synthetic-five"] {
            XCTAssertFalse(text.contains(secret), text)
        }
        XCTAssertTrue(text.contains(#"{"password":"[redacted]"}"#), text)
        XCTAssertTrue(text.contains(#""user":"qa""#), text)
    }

    func testUnterminatedQuotedCredentialIsRemovedToTheEndOfTheLine() {
        let text = DiagnosticRedactor.redact(#"""
        response {"accessToken":"synthetic-cut-off
        password='synthetic-open
        status 500
        """#)
        for secret in ["synthetic-cut-off", "synthetic-open"] { XCTAssertFalse(text.contains(secret), text) }
        XCTAssertTrue(text.hasSuffix("status 500"), text)
    }

    func testUnterminatedOptionalWrapperIsRemovedToTheEndOfTheLine() {
        let text = DiagnosticRedactor.redact(#"""
        password: Optional("synthetic-open
        token: Optional('synthetic-single
        secret: Optional("synthetic-escaped\"synthetic-after
        refreshToken: Optional(synthetic-bare
        status 500
        """#)
        for secret in ["synthetic-open", "synthetic-single", "synthetic-escaped", "synthetic-after", "synthetic-bare"] {
            XCTAssertFalse(text.contains(secret), text)
        }
        XCTAssertTrue(text.hasSuffix("status 500"), text)
    }
}
