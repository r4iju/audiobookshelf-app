import Foundation
import LegacyMigration
import XCTest

/// What an export archive written inside the legacy app may carry, and how it reports its work.
final class LegacyArchiveExportTests: XCTestCase {
    private var fixture: LegacyFixture!

    override func setUpWithError() throws {
        fixture = try LegacyFixture()
    }

    override func tearDown() {
        fixture.cleanUp()
    }

    private func archiveURL() -> URL {
        fixture.directory.appendingPathComponent("Exports/Audiobookshelf.absmigration")
    }

    func testAnArchiveCarriesReaderDataButNoServerCacheDeviceIdentityOrCredentials() throws {
        fixture.snapshot.preferences["serverSettings"] = #"{"version":"2.26.0","authOpenIDClientSecret":"cached-server-value"}"#
        fixture.snapshot.preferences["userSettings"] = #"{"mobileOrderBy":"addedAt"}"#
        try FileManager.default.createDirectory(at: archiveURL().deletingLastPathComponent(), withIntermediateDirectories: true)

        let archive = try LegacyArchive.write(fixture.snapshot, documents: fixture.documents, to: archiveURL())

        let snapshot = try LegacyArchive.open(archive).snapshot
        XCTAssertEqual(Set(snapshot.webStorage.keys), ["ereaderSettings", "ebookLocations-li-epub"],
                       "reader settings and location caches cross; the device identity and credential entries do not")
        XCTAssertEqual(snapshot.webStorage["ebookLocations-li-epub"], fixture.snapshot.webStorage["ebookLocations-li-epub"])
        XCTAssertEqual(Set(snapshot.preferences.keys), ["playerSettings", "bookshelfListView", "lastLibraryId", "theme", "lang", "userSettings"],
                       "the server settings cache is fetched again at sign-in and is not exported")
        let manifest = String(decoding: try Data(contentsOf: archive.appendingPathComponent(LegacyArchive.manifestName)), as: UTF8.self)
        for excluded in ["cached-server-value", "legacy-device-1", LegacyFixture.accessMarker, LegacyFixture.refreshMarker] {
            XCTAssertFalse(manifest.contains(excluded), "\(excluded) must not be exported")
        }
    }

    func testWritingAnArchiveReportsEveryFileAndByte() throws {
        try FileManager.default.createDirectory(at: archiveURL().deletingLastPathComponent(), withIntermediateDirectories: true)
        var reports: [LegacyArchiveProgress] = []

        let archive = try LegacyArchive.write(fixture.snapshot, documents: fixture.documents, to: archiveURL()) { reports.append($0) }

        let stored = try LegacyArchive.open(archive).storedPaths
        let first = try XCTUnwrap(reports.first)
        let last = try XCTUnwrap(reports.last)
        XCTAssertEqual(first.completedFiles, 0)
        XCTAssertEqual(first.completedBytes, 0)
        XCTAssertEqual(last.totalFiles, stored.count)
        XCTAssertEqual(last.completedFiles, last.totalFiles)
        XCTAssertEqual(last.completedBytes, last.totalBytes)
        let bytes = try stored.values.reduce(Int64(0)) { total, path in
            total + Int64(try Data(contentsOf: archive.appendingPathComponent("files").appendingPathComponent(path)).count)
        }
        XCTAssertEqual(last.totalBytes, bytes)
        XCTAssertEqual(reports.count, stored.count + 1)
        XCTAssertEqual(reports.map(\.completedFiles), Array(0...stored.count), "one report per copied file, in order")
    }
}
