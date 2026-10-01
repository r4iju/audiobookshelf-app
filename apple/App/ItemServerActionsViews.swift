import SwiftUI
import UIKit

/// An item's server actions in its details: its RSS feed, and sending its ebook to an e-reader the server lists for the user.
/// Each action appears only when the server would allow it; see `ItemServerActions`.
struct ItemServerActionsSection: View {
    @Environment(\.nativeStrings) private var l10n
    @EnvironmentObject private var realtime: NativeRealtime
    @StateObject private var actions: ItemServerActions
    private let catalog: CatalogStore
    @State private var started = false
    @State private var showingFeed = false
    @State private var choosingDevice = false

    init(itemID: String, catalog: CatalogStore) {
        _actions = StateObject(wrappedValue: ItemServerActions(api: catalog.api, itemID: itemID))
        self.catalog = catalog
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if actions.showsFeed {
                Button { showingFeed = true } label: {
                    Label(l10n(actions.feed == nil ? "Open RSS feed" : "RSS feed"), systemImage: "dot.radiowaves.left.and.right")
                }.accessibilityIdentifier("item-rss-feed")
            }
            if actions.canSendEbook {
                Button { choosingDevice = true } label: { Label(l10n("Send ebook to device"), systemImage: "paperplane") }
                    .disabled(actions.activity != nil).accessibilityIdentifier("send-ebook")
            }
            if case .sending(let device)? = actions.activity {
                ProgressView(l10n("Sending to {0}…", device))
            } else if let device = actions.sent {
                Label(l10n("Ebook sent to {0}", device), systemImage: "checkmark.circle").font(.callout).foregroundColor(ShelfStyle.secondaryText)
                    .accessibilityIdentifier("send-ebook-result")
            }
            if let error = actions.error, !showingFeed {
                if actions.loaded {
                    Text(ItemServerActionsText.failure(error, l10n: l10n)).font(.callout).foregroundColor(.red).accessibilityIdentifier("item-action-error")
                } else {
                    RecoveryCard(message: ConnectionStore.recovery(for: error)) { Task { await actions.load() } }
                }
            }
        }
        .onAppear { if !started { started = true; Task { await actions.load() } } }
        .onReceive(realtime.events) { event in
            guard catalog.owns(event) else { return }
            switch event.change {
            case .itemFeed(let itemID, let feed) where itemID == actions.itemID: actions.feedChanged(feed)
            case .authenticated where started: Task { await actions.load() }
            default: break
            }
        }
        .sheet(isPresented: $showingFeed) { RSSFeedSheet(actions: actions, presented: $showingFeed).nativeLocalization() }
        .actionSheet(isPresented: $choosingDevice) {
            ActionSheet(title: Text(l10n("Select a device")), buttons: actions.devices.map { device in
                .default(Text(device.name)) { NativeHaptic.impact("send"); Task { await actions.send(to: device) } }
            } + [.cancel(Text(l10n("Cancel")))])
        }
    }
}

@MainActor enum ItemServerActionsText {
    static func failure(_ error: Error, l10n: NativeStrings) -> String {
        switch error {
        case ItemServerActionError.invalidSlug: return l10n("The slug had to be modified. Check it, then open the feed again.")
        case APIError.http(403): return l10n("Your account is not allowed to do this on the server.")
        case APIError.http(404): return l10n("The server could not find this item, feed or device.")
        case APIError.http(400): return l10n("The server refused the request. A feed slug may already be in use, or the server could not send the ebook.")
        default: return ConnectionStore.recovery(for: error)
        }
    }
}

/// The baseline RSS feed modal: an open feed's address and settings for everyone, with Close feed for admins,
/// or the open form for admins when no feed is open.
struct RSSFeedSheet: View {
    @Environment(\.nativeStrings) private var l10n
    @ObservedObject var actions: ItemServerActions
    @Binding var presented: Bool
    @State private var slug = ""
    @State private var preventIndexing = true
    @State private var ownerName = ""
    @State private var ownerEmail = ""
    @State private var copied = false
    @State private var adjusted = false

    var body: some View {
        NavigationView {
            Form {
                if let feed = actions.feed {
                    openFeed(feed)
                } else if actions.canManageFeed {
                    newFeed
                }
                if let error = actions.error {
                    Text(ItemServerActionsText.failure(error, l10n: l10n)).foregroundColor(.red).accessibilityIdentifier("rss-error")
                }
            }
            .navigationTitle(l10n("RSS feed")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(l10n("Done")) { presented = false }.accessibilityIdentifier("rss-done") } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { slug = actions.itemID; copied = false; adjusted = false }
    }

    private func openFeed(_ feed: RSSFeed) -> some View {
        Group {
            Section(header: Text(l10n("RSS feed is open")).foregroundColor(ShelfStyle.secondaryText)) {
                Text(actions.feedURL(feed)).font(.callout).textSelection().accessibilityIdentifier("rss-feed-url")
                Button {
                    UIPasteboard.general.string = actions.feedURL(feed)
                    copied = true
                } label: { Label(l10n(copied ? "Copied" : "Copy feed URL"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityIdentifier("rss-copy")
            }
            if let meta = feed.meta {
                Section {
                    row(l10n("Prevent indexing"), meta.preventIndexing == false ? l10n("No") : l10n("Yes"), identifier: "rss-prevent-indexing")
                    if let name = meta.ownerName, !name.isEmpty { row(l10n("Custom owner name"), name, identifier: "rss-owner-name") }
                    if let email = meta.ownerEmail, !email.isEmpty { row(l10n("Custom owner email"), email, identifier: "rss-owner-email") }
                }
            }
            if actions.canManageFeed {
                Section {
                    Button(l10n("Close feed")) { Task { await actions.closeFeed(); if actions.feed == nil, actions.error == nil { presented = false } } }
                        .foregroundColor(.red).disabled(actions.activity != nil).accessibilityIdentifier("rss-close")
                }
            }
        }
    }

    private var newFeed: some View {
        Group {
            Section(header: Text(l10n("Feed slug")).foregroundColor(ShelfStyle.secondaryText), footer: Text(l10n("The feed URL will be {0}", actions.serverAddress + "/feed/" + slug)).foregroundColor(ShelfStyle.secondaryText)) {
                TextField(l10n("Feed slug"), text: $slug).autocapitalization(.none).disableAutocorrection(true).accessibilityIdentifier("rss-slug")
                if adjusted { Text(l10n("The slug had to be modified. Check it, then open the feed again.")).font(.footnote).foregroundColor(.orange).accessibilityIdentifier("rss-slug-adjusted") }
            }
            Section {
                Toggle(l10n("Prevent indexing"), isOn: $preventIndexing).accessibilityIdentifier("rss-prevent-indexing")
                TextField(l10n("Custom owner name"), text: $ownerName).accessibilityIdentifier("rss-owner-name")
                TextField(l10n("Custom owner email"), text: $ownerEmail).keyboardType(.emailAddress).autocapitalization(.none).accessibilityIdentifier("rss-owner-email")
            }
            if actions.serverAddress.lowercased().hasPrefix("http://") {
                Text(l10n("Important: most podcast apps require the RSS feed URL to use HTTPS.")).font(.footnote).foregroundColor(.orange)
            }
            if actions.hasEpisodesWithoutPubDate {
                Text(l10n("Important: one or more of your episodes do not have a Pub Date. Some podcast apps require this.")).font(.footnote).foregroundColor(.orange)
            }
            Section {
                Button(l10n("Open feed")) { open() }.disabled(actions.activity != nil).accessibilityIdentifier("rss-open")
                if actions.activity == .opening { ProgressView() }
            }
        }
    }

    private func open() {
        let sanitized = ItemServerActions.sanitizedSlug(slug)
        guard sanitized == slug else { slug = sanitized; adjusted = true; return }
        adjusted = false
        Task { await actions.openFeed(slug: slug, preventIndexing: preventIndexing, ownerName: ownerName, ownerEmail: ownerEmail) }
    }

    private func row(_ title: String, _ value: String, identifier: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier(identifier) }
    }
}

private extension View {
    @ViewBuilder func textSelection() -> some View {
        if #available(iOS 15.0, *) { self.textSelection(.enabled) } else { self }
    }
}
