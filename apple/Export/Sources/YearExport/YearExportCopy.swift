import Foundation

/// The language of one export: translations for the English templates below plus the locale for
/// numbers, months, durations and sizes. It is an immutable value held by the snapshot, so an image
/// shared later keeps the language chosen when the snapshot was built.
///
/// The export has no localization resources of its own. The app passes
/// `NativeStrings(language:).copy(YearExportCopy.templates)` and `language.locale`; anything without a
/// usable translation stays English. The legacy year-review canvases drew English text only, so
/// translations come from legacy keys with the same meaning, chosen by `apple/Localization`.
public struct YearExportCopy: Sendable {
    public static let english = YearExportCopy()

    public let locale: Locale
    private let translations: [String: String]

    /// Keeps only translations of known templates that use exactly the template's `{n}` placeholders,
    /// so a translation can neither drop a value nor show an argument that was never supplied.
    public init(translations: [String: String] = [:], locale: Locale = Locale(identifier: "en_US")) {
        self.locale = locale
        self.translations = translations.filter { english, translated in
            Self.known.contains(english)
                && !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.placeholders(translated) == Self.placeholders(english)
        }
    }

    /// Fills `{n}` from `arguments` in one pass, so names containing `{0}` are shown as written.
    func callAsFunction(_ english: String, _ arguments: CustomStringConvertible...) -> String {
        assert(Self.known.contains(english), "Add \"\(english)\" to YearExportCopy.templates")
        let template = translations[english] ?? english
        var text = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            text += rest[..<open]
            if let close = rest[open...].firstIndex(of: "}"), let index = Int(rest[rest.index(after: open)..<close]), arguments.indices.contains(index) {
                text += arguments[index].description
                rest = rest[rest.index(after: close)...]
            } else {
                text.append("{")
                rest = rest[rest.index(after: open)...]
            }
        }
        return text + rest
    }

    /// Headings drawn in capitals, upper-cased for the copy's own locale.
    func heading(_ text: String) -> String { text.uppercased(with: locale) }

    func title(of design: YearExportDesign) -> String {
        let copy = self
        switch design {
        case .highlights: return copy("Highlights")
        case .finishedBooks: return copy("Finished")
        case .topLists: return copy("Top Lists")
        case .compact: return copy("Compact")
        case .serverAdditions: return copy("Additions")
        case .serverPeople: return copy("People")
        case .serverGenres: return copy("Genres")
        }
    }

    func summary(of design: YearExportDesign) -> String {
        let copy = self
        switch design {
        case .highlights: return copy("Your totals with top narrator, genre, author and month.")
        case .finishedBooks: return copy("Your totals with covers of books you finished.")
        case .topLists: return copy("Your totals with your top authors and genres.")
        case .compact: return copy("A short banner with your book counts.")
        case .serverAdditions: return copy("Server totals with covers of books added this year.")
        case .serverPeople: return copy("Server totals with top authors and narrators.")
        case .serverGenres: return copy("Server totals with top authors and genres.")
        }
    }

    func title(of shape: YearExportShape) -> String {
        let copy = self
        switch shape {
        case .square: return copy("Square")
        case .portrait: return copy("Story")
        case .banner: return copy("Banner")
        }
    }

    /// Every English template the export draws, shares or shows, for `NativeStrings.copy`.
    public static let templates: [String] = [
        // Composer
        "Share {0}", "Share Server {0}", "Done", "Style", "Format", "Share Image", "Creating image",
        "Opens the share sheet with this image and a text summary.",
        "The image is created on this device from your {0} statistics.",
        "The image is created on this device from this server's {0} statistics.",
        "Highlights", "Finished", "Top Lists", "Compact", "Additions", "People", "Genres",
        "Your totals with top narrator, genre, author and month.", "Your totals with covers of books you finished.",
        "Your totals with your top authors and genres.", "A short banner with your book counts.",
        "Server totals with covers of books added this year.", "Server totals with top authors and narrators.",
        "Server totals with top authors and genres.",
        "Square", "Story", "Banner", "{0}, {1} image",
        // Shared text
        "My {0} in Audiobookshelf", "{0} hour of listening", "{0} hours of listening", "{0} minute of listening",
        "{0} minutes of listening", "{0} book finished", "{0} books finished", "{0} book listened to",
        "{0} books listened to", "{0} listening session", "{0} listening sessions", "Top author: {0}",
        "Top narrator: {0}", "Top genre: {0}", "Audiobookshelf server {0} in review", "{0} book added", "{0} books added",
        "{0} author added", "{0} authors added", "Collection: {0} (+{1} this year)", "Total duration: {0} (+{1} this year)",
        // Images
        "{0} year in review", "{0} server year in review", "book finished", "books finished", "book listened to",
        "books listened to", "session", "sessions", "hour listening", "hours listening", "minute listening",
        "minutes listening", "Time listening", "hour", "hours", "minute", "minutes", "Top narrator", "Top genre",
        "Top author", "Top month", "Longest book finished", "Top authors", "Top genres", "Top narrators",
        "Some books finished this year", "No listening recorded in {0}", "Press play and your year will fill in here.",
        "book added", "books added", "author added", "authors added", "In your library", "{0} book", "{0} books",
        "{0} listened this year", "Some additions include", "Collection grew to", "Total duration", "+{0} this year",
        "{0} days"
    ]

    private static let known = Set(templates)

    static func placeholders(_ text: String) -> Set<String> {
        var found = Set<String>()
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            found.insert(String(rest[open...close]))
            rest = rest[rest.index(after: close)...]
        }
        return found
    }
}
