import XCTest
@testable import NativeDiagnostics

final class DiagnosticReportTests: XCTestCase {
    private let generated = Date(timeIntervalSince1970: 1_790_000_000)
    private var events: [DiagnosticEvent] {
        [DiagnosticEvent(category: .connection, message: "The server could not be reached.", detail: "NSURLErrorDomain -1004 http://127.0.0.1:25799/abs/login", date: generated.addingTimeInterval(-60)),
         DiagnosticEvent(category: .media, message: "Audio could not be played.", detail: nil, date: generated.addingTimeInterval(-10))]
    }
    private var sections: [DiagnosticReport.Section] {
        [DiagnosticReport.Section(title: "App", lines: [.init("Version", "1.0.0 (1)"), .init("Language", "Deutsch (de)")]),
         DiagnosticReport.Section(title: "Connection", lines: [.init("Server", "https://qa:pw-77@books.example.lan/abs?token=zz-99"), .init("Pending listening", "2")])]
    }

    func testReportListsStatusThenNewestEventsFirst() {
        let report = DiagnosticReport.text(sections: sections, events: events, generated: generated, maskingAddresses: false)
        XCTAssertTrue(report.contains("Version: 1.0.0 (1)"), report)
        XCTAssertTrue(report.contains("Pending listening: 2"), report)
        let media = report.range(of: "[media] Audio could not be played.")
        let connection = report.range(of: "[connection] The server could not be reached.")
        XCTAssertNotNil(media); XCTAssertNotNil(connection)
        if let media, let connection { XCTAssertLessThan(media.lowerBound, connection.lowerBound) }
        XCTAssertTrue(report.contains("NSURLErrorDomain -1004 http://127.0.0.1:25799/abs/login"), report)
    }

    func testReportIsRedactedEvenWhenStatusValuesContainSecrets() {
        let report = DiagnosticReport.text(sections: sections, events: events, generated: generated, maskingAddresses: false)
        XCTAssertTrue(report.contains("https://books.example.lan/abs"), report)
        XCTAssertFalse(report.contains("pw-77"), report)
        XCTAssertFalse(report.contains("zz-99"), report)
    }

    func testMaskedReportHidesEveryServerAddress() {
        let report = DiagnosticReport.text(sections: sections, events: events, generated: generated, maskingAddresses: true)
        XCTAssertFalse(report.contains("books.example.lan"), report)
        XCTAssertFalse(report.contains("127.0.0.1"), report)
        XCTAssertTrue(report.contains("http://[server]/abs/login"), report)
    }
}
