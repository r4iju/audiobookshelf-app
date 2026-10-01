import Combine
import Foundation

/// An open RSS feed, as `Feed.toOldJSONMinified()` reports it. `feedUrl` is a path on the server, such as `/feed/<slug>`.
public struct RSSFeed: Decodable, Equatable, Sendable {
    public struct Meta: Decodable, Equatable, Sendable {
        public let title: String?
        public let preventIndexing: Bool?
        public let ownerName: String?
        public let ownerEmail: String?
    }
    public let id: String
    public let feedUrl: String
    public let meta: Meta?
}

/// Only the name is kept: it is what the server looks the device up by, and its address is not the app's to show.
public struct EReaderDevice: Decodable, Hashable, Sendable {
    public let name: String
}

/// The part of `POST /api/authorize` the item actions need.
public struct SessionAuthorization: Decodable {
    public struct User: Decodable {
        public let id: String
        public let type: String?
        public var isAdminOrUp: Bool { type == "root" || type == "admin" }
    }
    public let user: User
    public let ereaderDevices: [EReaderDevice]?
}

public struct ItemActionsDetail: Decodable {
    struct Present: Decodable { init(from decoder: Decoder) throws {} }
    struct Episode: Decodable { let pubDate: String? }
    struct Media: Decodable {
        let ebookFile: Present?
        let tracks: [Present]?
        let episodes: [Episode]?
    }
    let id: String
    let mediaType: String?
    let media: Media
    let rssFeed: RSSFeed?
}

public enum ItemServerActionError: Error, Equatable {
    /// The slug was empty or changed by sanitizing; the baseline asks to run again with the sanitized slug.
    case invalidSlug
}

/// RSS feed and send-to-device actions for one item, for the sign-in it was created under.
@MainActor public final class ItemServerActions: ObservableObject {
    public enum Activity: Equatable { case opening, closing, sending(String) }
    @Published public private(set) var loaded = false
    @Published public private(set) var feed: RSSFeed?
    @Published public private(set) var devices: [EReaderDevice] = []
    @Published public private(set) var activity: Activity?
    @Published public private(set) var error: Error?
    /// The device the ebook was last sent to.
    @Published public private(set) var sent: String?
    public let itemID: String
    private let api: APIClient
    private let signIn: OpenedSignIn
    private var isAdmin = false
    private var hasAudio = false
    private var hasEbook = false
    private var isBook = false
    /// Counts feed changes, from realtime events or this device's own open and close, so a load, open or close that
    /// started before one does not undo it.
    private var feedChanges = 0
    /// Counts loads; only the latest one publishes its result or error.
    private var loads = 0

    public init(api: APIClient, itemID: String) {
        self.api = api
        self.itemID = itemID
        signIn = OpenedSignIn(api: api)
    }

    /// Like the baseline: anyone sees an open feed, and only admins can open one, for an item with audio.
    public var showsFeed: Bool { loaded && (feed != nil || isAdmin && hasAudio) }
    /// The server's feed routes are admin only.
    public var canManageFeed: Bool { loaded && isAdmin }
    public var canSendEbook: Bool { loaded && isBook && hasEbook && !devices.isEmpty }
    /// Podcast apps may skip feed episodes without a published date, so the baseline warns before opening.
    @Published public private(set) var hasEpisodesWithoutPubDate = false

    public var serverAddress: String {
        var address = api.credentials?.server ?? ""
        while address.hasSuffix("/") { address.removeLast() }
        return address
    }

    public func feedURL(_ feed: RSSFeed) -> String {
        feed.feedUrl.lowercased().hasPrefix("http") ? feed.feedUrl : serverAddress + feed.feedUrl
    }

    /// The baseline `$sanitizeSlug`, including its quirks: only the first dot becomes a dash, and the range ` -_` keeps
    /// ASCII from space to underscore.
    public static func sanitizedSlug(_ text: String) -> String {
        var slug = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let from = Array("àáäâèéëêìíïîòóöôùúüûñçěščřžýúůďťň·/,:;"), to = Array("aaaaeeeeiiiioooouuuuncescrzyuudtn-----")
        slug = String(slug.map { character in from.firstIndex(of: character).map { to[$0] } ?? character })
        if let dot = slug.firstIndex(of: ".") { slug.replaceSubrange(dot...dot, with: "-") }
        slug = String(slug.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || (" "..."_").contains($0) }.map(Character.init))
        slug = slug.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "/", with: "")
        return slug
    }

    public func load() async {
        loads += 1
        let load = loads
        let authorization = signIn.revision
        let changes = feedChanges
        do {
            try await signIn.confirm()
            async let session = api.sessionAuthorization(authorization: authorization)
            async let detail = api.itemActions(id: itemID, authorization: authorization)
            let (account, item) = try await (session, detail)
            guard load == loads, signIn.owns(userID: account.user.id) else { return }
            isAdmin = account.user.isAdminOrUp
            devices = account.ereaderDevices ?? []
            isBook = item.mediaType == "book"
            hasEbook = item.media.ebookFile != nil
            hasAudio = !(item.media.tracks ?? []).isEmpty || !(item.media.episodes ?? []).isEmpty
            hasEpisodesWithoutPubDate = (item.media.episodes ?? []).contains { ($0.pubDate ?? "").isEmpty }
            if feedChanges == changes { feed = item.rssFeed }
            error = nil
            loaded = true
        } catch {
            guard load == loads else { return }
            report(error)
        }
    }

    /// Another client opened (`feed`) or closed (`nil`) this item's feed, as received by this sign-in.
    public func feedChanged(_ feed: RSSFeed?) {
        guard signIn.isCurrent else { return }
        feedChanges += 1
        self.feed = feed
    }

    public func openFeed(slug: String, preventIndexing: Bool, ownerName: String, ownerEmail: String) async {
        guard activity == nil, showsFeed, canManageFeed, feed == nil, signIn.isCurrent else { return }
        guard !slug.isEmpty, slug == Self.sanitizedSlug(slug) else { error = ItemServerActionError.invalidSlug; return }
        await perform(.opening) { authorization in
            let changes = self.feedChanges
            let opened = try await self.api.openFeed(itemID: self.itemID, serverAddress: self.serverAddress, slug: slug, preventIndexing: preventIndexing,
                                                     ownerName: ownerName, ownerEmail: ownerEmail, authorization: authorization)
            return { self.applyOwnFeed(opened, ifUnchangedSince: changes) }
        }
    }

    public func closeFeed() async {
        guard activity == nil, canManageFeed, let feed, signIn.isCurrent else { return }
        await perform(.closing) { authorization in
            let changes = self.feedChanges
            try await self.api.closeFeed(id: feed.id, authorization: authorization)
            return { self.applyOwnFeed(nil, ifUnchangedSince: changes) }
        }
    }

    public func send(to device: EReaderDevice) async {
        guard activity == nil, canSendEbook, devices.contains(device), signIn.isCurrent else { return }
        sent = nil
        await perform(.sending(device.name)) { authorization in
            try await self.api.sendEbookToDevice(itemID: self.itemID, deviceName: device.name, authorization: authorization)
            return { self.sent = device.name }
        }
    }

    /// Publishes this device's own open or close unless another client changed the feed meanwhile. It counts as a feed
    /// change, so a load that read the item before it cannot restore the previous feed.
    private func applyOwnFeed(_ feed: RSSFeed?, ifUnchangedSince changes: Int) {
        guard feedChanges == changes else { return }
        feedChanges += 1
        self.feed = feed
    }

    /// Runs one request for this sign-in and applies its result only if the sign-in is still current afterwards.
    private func perform(_ kind: Activity, _ action: (UUID) async throws -> () -> Void) async {
        activity = kind
        error = nil
        defer { activity = nil }
        do {
            try await signIn.confirm()
            let apply = try await action(signIn.revision)
            if signIn.isCurrent { apply() }
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard signIn.isCurrent, !(error is CancellationError) else { return }
        self.error = error
    }
}
