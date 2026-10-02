import UIKit
import XCTest
@testable import YearExport

@MainActor final class YearExportShareTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("YearExportShareTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testFailedPNGWriteLeavesNoTemporaryFolder() {
        XCTAssertThrowsError(try YearExportShareFile(artifact: artifact(fileName: "missing/folder.png"), root: root))
        XCTAssertEqual(leftovers(), [])
    }

    func testFinishingTheShareSheetRemovesTheFile() throws {
        let request = ShareRequest(artifact: artifact(), root: root)
        let url = try XCTUnwrap(request.file?.url)
        XCTAssertEqual(try Data(contentsOf: url), artifact().pngData)
        var finished = false
        let activity = YearExportActivity.controller(for: request) { finished = true }
        activity.completionWithItemsHandler?(nil, false, nil, nil)
        XCTAssertTrue(finished)
        XCTAssertEqual(leftovers(), [])
    }

    func testFileLivesExactlyAsLongAsTheShareSheetWhenNoCompletionArrives() throws {
        var activity: UIActivityViewController?
        var url: URL?
        autoreleasepool {
            let request = ShareRequest(artifact: artifact(), root: root)
            url = request.file?.url
            activity = YearExportActivity.controller(for: request) {}
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(url).path), "deleted while the consumer can still read it")
        weak var released = activity
        autoreleasepool { activity = nil }
        let deadline = Date().addingTimeInterval(5)
        while released != nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNil(released, "share sheet still alive")
        XCTAssertEqual(leftovers(), [])
    }

    func testPresentingFromADetachedComposerFailsAndReleasesTheFile() {
        autoreleasepool {
            let request = ShareRequest(artifact: artifact(), root: root)
            XCTAssertFalse(YearExportActivity.present(request, from: UIViewController()) {})
        }
        XCTAssertEqual(leftovers(), [])
    }

    private func artifact(fileName: String = "audiobookshelf_my_2025.png") -> YearExportArtifact {
        YearExportArtifact(snapshotID: UUID(), year: 2025, layout: YearExportLayout(design: .compact, shape: .banner)!,
                           pngData: Data([0x89, 0x50, 0x4E, 0x47]), fileName: fileName, shareText: "My 2025", accessibilityLabel: "")
    }

    private func leftovers() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] }
}
