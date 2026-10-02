import CryptoKit
import Foundation
import LegacyMigration
import LegacyRealmExport
import RealmSwift
import XCTest

/// Runs the exporter inside a process whose default Realm schema is the legacy app's own model
/// classes, compiled from the legacy sources, the way the export plugin runs inside the legacy app.
final class LegacyAppCompatibilityTests: XCTestCase {
    private static let accessToken = "SYNTHETIC-APP-ACCESS-TOKEN"

    private var directory: URL!
    private var documents: URL!
    private var previousConfiguration: Realm.Configuration!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-app-\(UUID().uuidString)").resolvingSymlinksInPath()
        documents = directory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        AbsDownloader.documents = documents
        previousConfiguration = Realm.Configuration.defaultConfiguration
        // As AppDelegate configures it: the default schema (the app's classes), version 21.
        Realm.Configuration.defaultConfiguration = Realm.Configuration(fileURL: documents.appendingPathComponent("default.realm"), schemaVersion: 21)
        suite = "legacy-app-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        Realm.Configuration.defaultConfiguration = previousConfiguration
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Downloaded files only; the live database belongs to the running app.
    private func downloadsDigest() throws -> [String: String] {
        var result: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: documents, includingPropertiesForKeys: nil)! where !url.lastPathComponent.hasPrefix("default.realm") {
            guard (try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular else { continue }
            result[url.path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    func testTheExporterReadsTheAppsOwnDatabaseInTheSameProcessAndLeavesTheAppUsable() throws {
        try LegacyAppSeed(documents: documents, address: "https://books.example.test", token: Self.accessToken).write()
        let downloads = try downloadsDigest()
        let work = directory.appendingPathComponent("Work")

        let archive = try LegacyArchiveExporter.export(
            documents: documents, defaults: defaults,
            webStorage: ["ereaderSettings": #"{"fontScale":1.1}"#, "ebookLocations-li-1": #"{"locations":"[]"}"#, "refresh_token_conn-1": "SYNTHETIC-REFRESH"],
            workDirectory: work, to: directory.appendingPathComponent("Exports/Audiobookshelf.absmigration"),
            copyRealm: { try Realm().writeCopy(toFile: $0) }
        )

        XCTAssertEqual(try downloadsDigest(), downloads, "downloads are only read")
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        for case let url as URL in FileManager.default.enumerator(at: archive, includingPropertiesForKeys: nil)! {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains(Self.accessToken), "credential exported in \(url.lastPathComponent)")
            XCTAssertFalse(text.contains("SYNTHETIC-REFRESH"), "refresh token exported in \(url.lastPathComponent)")
            XCTAssertFalse(text.contains("request failed"), "log entry exported in \(url.lastPathComponent)")
        }

        // The app's own classes keep working after the exporter's schema was loaded.
        let realm = try Realm()
        XCTAssertEqual(realm.objects(ServerConnectionConfig.self).first?.token, Self.accessToken)
        XCTAssertEqual(Database.shared.getLocalFile(localFileId: "lf-epub")?.filename, "book.epub")
        try realm.write { realm.objects(LocalMediaProgress.self).first?.currentTime = 50 }
        XCTAssertEqual(Database.shared.getLocalMediaProgress(localMediaProgressId: "local_li-1")?.currentTime, 50)
        XCTAssertEqual(realm.object(ofType: LocalLibraryItem.self, forPrimaryKey: "local_li-1")?.media?.ebookFile?.ebookFormat, "epub")

        let migrator = LegacyMigrator(root: directory.appendingPathComponent("NativeContainer/LegacyMigration"))
        let outcome = try migrator.migrate(try LegacyArchive.open(archive))
        let account = try XCTUnwrap(MigrationAccount(address: "https://books.example.test", userID: "user-1"))
        XCTAssertEqual(outcome.accounts.map(\.account), [account])
        XCTAssertEqual(outcome.accounts.first?.credentials, .reauthenticationRequired)
        XCTAssertEqual(outcome.settings.device?.jumpForwardTime, 30)
        XCTAssertEqual(Set(outcome.settings.webStorage.keys), ["ereaderSettings", "ebookLocations-li-1"])
        let book = try XCTUnwrap(outcome.downloads.first { $0.libraryItemID == "li-1" })
        XCTAssertTrue(book.complete)
        XCTAssertEqual(book.title, "Synthetic Book")
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.tracks.first?.file))), Data("app-audio".utf8))
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(book.ebook?.file))), Data("PK-app-epub".utf8))
        let progress = try XCTUnwrap(outcome.progress.first { $0.libraryItemID == "li-1" })
        XCTAssertEqual(progress.currentTime, 42, "the export is the database as it was when exported")
        XCTAssertEqual(progress.reading?.raw, "epubcfi(/6/4!/4/2/1:0)")
        let interrupted = try XCTUnwrap(outcome.interruptedDownloads.first { $0.libraryItemID == "li-2" })
        XCTAssertEqual(try Data(contentsOf: migrator.fileURL(for: XCTUnwrap(interrupted.parts.first?.file))), Data("app-finished-part".utf8))
    }
}
