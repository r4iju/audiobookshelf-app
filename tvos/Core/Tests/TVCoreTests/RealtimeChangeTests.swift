import XCTest
@testable import TVCore

final class RealtimeChangeTests: XCTestCase {
    private let owner = try! AccountIdentity(server: "https://books.example/abs", userID: "user-a")

    private func change(_ name: String, _ json: String) -> RealtimeChange? {
        RealtimeChange(ServerEvent(name: name, data: Data(json.utf8)), owner: owner)
    }

    func testServer230ProgressFromAnotherSessionNamesTheChangedMedia() {
        let payload = #"{"id":"progress-1","sessionId":"other","deviceDescription":"Web","data":{"id":"progress-1","userId":"user-a","libraryItemId":"book-3","episodeId":"episode-2","currentTime":12,"duration":20,"progress":0.6,"isFinished":false,"lastUpdate":1}}"#
        guard case .progress(let itemID, let episodeID, let sessionID)? = change("user_item_progress_updated", payload) else { return XCTFail("Progress was not recognised") }
        XCTAssertEqual(itemID, "book-3"); XCTAssertEqual(episodeID, "episode-2"); XCTAssertEqual(sessionID, "other")
    }

    func testEventsAddressedToAnotherAccountAreRejected() {
        XCTAssertNil(change("user_item_progress_updated", #"{"id":"p","sessionId":"s","data":{"userId":"user-b","libraryItemId":"book-3"}}"#))
        XCTAssertNil(change("user_updated", #"{"id":"user-b","username":"other","mediaProgress":[]}"#))
        XCTAssertNil(change("playlist_updated", #"{"id":"playlist-1","userId":"user-b","libraryId":"books","name":"Theirs"}"#))
        XCTAssertNil(change("init", #"{"userId":"user-b"}"#))
    }

    func testUserUpdatesForTheOwnerRequestAProgressRefresh() {
        guard case .user? = change("user_updated", #"{"id":"user-a","username":"qa","mediaProgress":[]}"#) else { return XCTFail("Owner update was not recognised") }
    }

    func testLibraryItemEventsCarryTheExpandedItemOrItsIdentity() {
        let item = #"{"id":"book-1","libraryId":"books","mediaType":"book","media":{"metadata":{"title":"Renamed"}}}"#
        guard case .itemsUpdated(let updated)? = change("item_updated", item) else { return XCTFail("Item update was not recognised") }
        XCTAssertEqual(updated.map(\.title), ["Renamed"])
        guard case .itemsUpdated(let batch)? = change("items_updated", "[" + item + "]") else { return XCTFail("Batch update was not recognised") }
        XCTAssertEqual(batch.map(\.id), ["book-1"])
        guard case .itemsAdded(let libraries)? = change("items_added", "[" + item + "]") else { return XCTFail("Batch addition was not recognised") }
        XCTAssertEqual(libraries, ["books"])
        guard case .itemRemoved(let removed)? = change("item_removed", #"{"id":"book-9"}"#) else { return XCTFail("Removal was not recognised") }
        XCTAssertEqual(removed, "book-9")
    }

    func testPlaylistAndCollectionEventsIdentifyTheGroup() {
        guard case .group(let kind, let id, let removed)? = change("playlist_removed", #"{"id":"playlist-1","userId":"user-a","libraryId":"books","name":"Mine"}"#) else { return XCTFail("Playlist removal was not recognised") }
        XCTAssertEqual(kind, .playlist); XCTAssertEqual(id, "playlist-1"); XCTAssertTrue(removed)
        guard case .group(let collection, "collection-1", false)? = change("collection_updated", #"{"id":"collection-1","libraryId":"books","name":"Shared"}"#) else { return XCTFail("Collection update was not recognised") }
        XCTAssertEqual(collection, .collection)
    }

    func testItemFeedEventsCarryTheFeedOrItsClosing() {
        let feed = #"{"id":"saga-feed","entityType":"libraryItem","entityId":"book-1","feedUrl":"/feed/saga-feed","meta":{"title":"Saga","description":null,"preventIndexing":true,"ownerName":"Owner","ownerEmail":null}}"#
        guard case .itemFeed(let opened, let current)? = change("rss_feed_open", feed) else { return XCTFail("Feed opening was not recognised") }
        XCTAssertEqual(opened, "book-1"); XCTAssertEqual(current?.feedUrl, "/feed/saga-feed"); XCTAssertEqual(current?.meta?.ownerName, "Owner")
        guard case .itemFeed(let closed, nil)? = change("rss_feed_closed", feed) else { return XCTFail("Feed closing was not recognised") }
        XCTAssertEqual(closed, "book-1")
        XCTAssertNil(change("rss_feed_open", feed.replacingOccurrences(of: "libraryItem", with: "collection")), "Collection and series feeds are not an item's")
        XCTAssertNil(change("rss_feed_open", #"{"entityType":"libraryItem","entityId":"book-1"}"#))
    }

    func testPodcastDownloadResultsStillReachTheQueue() {
        guard case .episodeDownloadFinished(let job)? = change("episode_download_finished", #"{"id":"download-1","libraryItemId":"podcast","isFinished":true,"failed":true,"url":"http://feed/a.mp3"}"#) else { return XCTFail("Download result was not recognised") }
        XCTAssertEqual(job.id, "download-1"); XCTAssertTrue(job.failed)
    }

    func testUnsupportedOrMalformedEventsAreIgnored() {
        XCTAssertNil(change("task_started", #"{"id":"task"}"#))
        XCTAssertNil(change("item_updated", #"{"unexpected":true}"#))
        XCTAssertNil(change("user_item_progress_updated", #"{"data":{}}"#))
    }
}
