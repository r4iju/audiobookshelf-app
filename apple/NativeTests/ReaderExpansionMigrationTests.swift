import XCTest

@MainActor final class ReaderExpansionMigrationTests: XCTestCase {
    func testLegacyComicPagesAndOpaqueMobiPlacesRemainAssociatedThroughAdoptionAndRelaunch() async throws {
        let h = try AdoptionHarness()
        defer { h.cleanUp() }
        let account = AdoptionHarness.identity(AdoptionHarness.alice)
        for (format, location) in [("cbz", "7"), ("cbr", "12"), ("mobi", "legacy-unknown-location"), ("azw3", "mobi:1:2:4"), ("epub", "legacy-invalid-cfi"), ("pdf", "legacy-invalid-page")] {
            try h.addEbook("li-" + format, format: format, data: Data((format + " retained bytes").utf8), location: location, fraction: 0.5)
        }
        let outcome = try h.migrate()
        let original = try h.originalDigests()
        _ = try await h.adoption.apply(outcome: outcome, migrator: h.migrator)
        h.signIn(AdoptionHarness.alice); h.openStores()
        for (format, location) in [("cbz", "7"), ("cbr", "12"), ("mobi", "legacy-unknown-location"), ("azw3", "mobi:1:2:4"), ("epub", "legacy-invalid-cfi"), ("pdf", "legacy-invalid-page")] {
            let entry = try XCTUnwrap(h.entry("li-" + format))
            XCTAssertEqual(entry.ebook?.format, format)
            XCTAssertEqual(try Data(contentsOf: h.downloads.ebookURL(entry)), Data((format + " retained bytes").utf8))
            let position = try XCTUnwrap(h.reading.position(account: account, itemID: "li-" + format, format: format))
            XCTAssertEqual(position.location, location)
            if ["mobi", "epub", "pdf"].contains(format) { XCTAssertFalse(position.pending, "Unknown location must be retained without automatic publication") }
        }
        XCTAssertEqual(try h.originalDigests(), original)
        XCTAssertEqual(try h.migrator.committedOutcome(), outcome)
    }
}
