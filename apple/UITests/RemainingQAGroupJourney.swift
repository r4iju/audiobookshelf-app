import XCTest

/// Story 22: management the server refuses must fail clearly, without suggesting a retry or a partial save.
@MainActor final class RemainingQAGroupJourney: RemainingQAJourney {
    struct Collection: Decodable {
        struct Book: Decodable { let id: String }
        let id: String
        let books: [Book]
    }
    struct GroupObservations: Decodable { let collections: [Collection] }

    func collections() async throws -> [Collection] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: Self.server + "/__fixture__/observations")!)
        return try JSONDecoder().decode(GroupObservations.self, from: data).collections
    }

    func testServerRejectedCollectionEditSaysTheAccountIsNotAllowedAndSavesNothing() async throws {
        signIn()
        let app = XCUIApplication()
        app.buttons["Collections"].tap()
        XCTAssertTrue(app.buttons["group-collection-evening"].waitForExistence(timeout: 10))
        app.buttons["group-collection-evening"].tap()
        app.buttons["Edit collection"].tap()
        try await configure("group-forbidden")
        app.buttons["move-up-book-1:"].tap()
        app.buttons["Save group"].tap()
        let error = app.staticTexts["group-save-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("not allowed"), error.label)
        XCTAssertFalse(error.label.contains("may already be saved"), "Nothing was saved, so the message must not suggest otherwise: \(error.label)")
        XCTAssertTrue(app.buttons["Save group"].exists, "The editor stays open with the requested changes")
        let saved = try await collections().first { $0.id == "collection-evening" }
        XCTAssertEqual(saved?.books.map(\.id), ["book-2", "book-1"])
    }

    /// Server 2.30 authorizes collection deletion by `permissions.delete` alone, and an admin's default is false, so an
    /// admin without it must not be offered Delete collection. Editing stays, because the default admin can update.
    func testAdminWithoutDeletePermissionIsNotOfferedCollectionDeletion() async throws {
        try await configure("podcast-admin")
        signIn()
        let app = XCUIApplication()
        app.buttons["Collections"].tap()
        XCTAssertTrue(app.buttons["group-collection-evening"].waitForExistence(timeout: 10))
        app.buttons["group-collection-evening"].tap()
        XCTAssertTrue(app.buttons["Edit collection"].waitForExistence(timeout: 10))
        app.buttons["Group actions"].tap()
        XCTAssertTrue(app.buttons["Refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete collection"].exists)
    }
}
