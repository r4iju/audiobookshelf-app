import XCTest
@testable import NativeDiagnostics

final class DiagnosticLogTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("events.json") }
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func log(limit: Int = 200) -> DiagnosticLog { DiagnosticLog(file: file, limit: limit) { [unowned self] in clock } }

    func testSecretsNeverReachTheSavedFile() throws {
        try log().record(.connection, message: "Login to http://qa:hunter2@127.0.0.1:25799/abs?token=leak-123 failed")
        let saved = try String(contentsOf: file)
        XCTAssertFalse(saved.contains("hunter2"))
        XCTAssertFalse(saved.contains("leak-123"))
        XCTAssertTrue(saved.contains("127.0.0.1:25799"))
    }

    func testEventsSurviveRelaunchInRecordedOrder() throws {
        try log().record(.connection, message: "first")
        clock.addTimeInterval(5)
        try log().record(.media, message: "second", detail: "NSURLErrorDomain -1100")
        let events = log().events
        XCTAssertEqual(events.map(\.message), ["first", "second"])
        XCTAssertEqual(events.map(\.category), [.connection, .media])
        XCTAssertEqual(events.last?.detail, "NSURLErrorDomain -1100")
        XCTAssertEqual(events.last?.lastDate, clock)
    }

    func testRepeatedFailuresAreCountedInsteadOfFloodingTheLog() throws {
        let log = log()
        try log.record(.sync, message: "Listening could not be saved")
        clock.addTimeInterval(30)
        try log.record(.sync, message: "Listening could not be saved")
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.events[0].count, 2)
        XCTAssertEqual(log.events[0].lastDate, clock)
        XCTAssertEqual(log.events[0].firstDate, Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testOnlyTheNewestEventsAreRetained() throws {
        let log = log(limit: 3)
        for index in 1...5 { try log.record(.server, message: "failure \(index)") }
        XCTAssertEqual(DiagnosticLog(file: file, limit: 3).events.map(\.message), ["failure 3", "failure 4", "failure 5"])
    }

    func testClearingRemovesSavedEvents() throws {
        let log = log()
        try log.record(.download, message: "Download failed")
        try log.clear()
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(self.log().events.isEmpty)
    }

    func testUnreadableHistoryDoesNotPreventNewDiagnostics() throws {
        try Data("not json".utf8).write(to: file)
        let log = log()
        XCTAssertTrue(log.events.isEmpty)
        try log.record(.media, message: "Playback failed")
        XCTAssertEqual(self.log().events.map(\.message), ["Playback failed"])
    }
}
