import Foundation
import LegacyMigration
import RealmSwift
import XCTest

/// Support for the simulator export journey (`apple/Migration/LegacyExportJourney/run.sh`), skipped
/// unless it sets its environment: writes the synthetic library with the legacy app's own model
/// classes, and checks the package the app saved through Files.
final class LegacyJourneyFixture: XCTestCase {
    static let token = "SYNTHETIC-JOURNEY-ACCESS-TOKEN"

    func testWriteTheSimulatorJourneyLibrary() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["ABS_LEGACY_JOURNEY_FIXTURE"], let epub = environment["ABS_LEGACY_JOURNEY_EPUB"] else {
            throw XCTSkip("ABS_LEGACY_JOURNEY_FIXTURE and ABS_LEGACY_JOURNEY_EPUB are not set")
        }
        let documents = URL(fileURLWithPath: output).appendingPathComponent("Documents")
        try? FileManager.default.removeItem(at: documents)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-journey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let previous = Realm.Configuration.defaultConfiguration
        defer {
            Realm.Configuration.defaultConfiguration = previous
            try? FileManager.default.removeItem(at: work)
        }
        Realm.Configuration.defaultConfiguration = Realm.Configuration(fileURL: work.appendingPathComponent("default.realm"), schemaVersion: 21)
        try LegacyAppSeed(documents: documents, address: environment["ABS_LEGACY_JOURNEY_ADDRESS"] ?? "http://127.0.0.1:19811",
                          token: Self.token, epub: Data(contentsOf: URL(fileURLWithPath: epub))).write()
        try autoreleasepool {
            try Realm().writeCopy(toFile: documents.appendingPathComponent("default.realm"))
        }
    }

    func testTheSavedJourneyPackageCarriesTheLibraryWithoutCredentials() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let package = environment["ABS_LEGACY_JOURNEY_PACKAGE"], let epub = environment["ABS_LEGACY_JOURNEY_EPUB"] else {
            throw XCTSkip("ABS_LEGACY_JOURNEY_PACKAGE and ABS_LEGACY_JOURNEY_EPUB are not set")
        }
        let url = URL(fileURLWithPath: package)
        for case let file as URL in FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)! {
            guard let data = try? Data(contentsOf: file) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains(Self.token), "credential in \(file.lastPathComponent)")
            XCTAssertFalse(text.contains("request failed"), "log entry in \(file.lastPathComponent)")
        }
        let archive = try LegacyArchive.open(url)
        let webStorage = archive.snapshot.webStorage
        XCTAssertTrue(webStorage["ereaderSettings"]?.contains("serif") == true, "the reader setting chosen in the app crossed: \(webStorage.keys.sorted())")
        XCTAssertTrue(webStorage.keys.contains { $0.hasPrefix("ebookLocations-") }, "the reader's location cache crossed: \(webStorage.keys.sorted())")
        XCTAssertNil(webStorage["absDeviceId"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-journey-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let migrator = LegacyMigrator(root: root.appendingPathComponent("LegacyMigration"))
        let outcome = try migrator.migrate(archive)
        XCTAssertEqual(outcome.accounts.first?.credentials, .reauthenticationRequired)
        XCTAssertEqual(outcome.settings.device?.jumpForwardTime, 30)
        let book = try XCTUnwrap(outcome.downloads.first { $0.libraryItemID == "li-1" })
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.ebook?.file))), try Data(contentsOf: URL(fileURLWithPath: epub)))
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.tracks.first?.file))), Data("app-audio".utf8))
        let progress = try XCTUnwrap(outcome.progress.first { $0.libraryItemID == "li-1" })
        XCTAssertEqual(progress.reading?.raw.hasPrefix("epubcfi("), true)
        XCTAssertNotNil(outcome.interruptedDownloads.first { $0.libraryItemID == "li-2" })
    }
}
